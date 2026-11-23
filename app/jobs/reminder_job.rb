# Every minute (config/recurring.yml), notifications on the clock rather
# than on a change:
#
# - Event reminders: an event someone has accepted starts within their
#   chosen lead time (5/15/30/60 minutes). Category "event_reminders".
# - To-do digest: in the hour they chose, on the household's clock, one
#   list of their open to-dos due today, if there are any. Category
#   "todo_digest" (off by default), and only if they want push or email.
#
# Each reminder is claimed in reminders_sent before it's sent, so double
# ticks and catch-ups never repeat one. Only accepted assignments count:
# nothing for pending or declined ones, nor for items "for anyone".
class ReminderJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    now = now.change(sec: 0)
    remind_events(now)
    send_digests(now)
  end

  private

  def remind_events(now)
    horizon = now + User::REMINDER_LEADS.max.minutes
    Task.open.timed.where(starts_at: (now + 1.second)..horizon)
        .includes(:household, :location, assignments: :user).find_each do |task|
      task.assignments.select(&:accepted?).each do |assignment|
        remind(task, assignment.user, now)
      end
    end
  end

  def remind(task, person, now)
    return if task.starts_at > now + person.reminder_lead_minutes.minutes
    return unless ReminderSent.claim(user_id: person.id, household_id: task.household_id, task_id: task.id, kind: "event",
                                     occurrence_starts_at: task.starts_at)

    zone = task.household.zone || Time.zone_default
    minutes = ((task.starts_at - now) / 60).ceil
    details = ["Starts in #{minutes == 60 ? '1 hour' : "#{minutes} minutes"}", (task.place_name if task.visible_to?(person))].compact
    Notifier.notify(person, category: "event_reminders", household: task.household, now: now,
                            title: "#{task.title_for(person)} at #{task.starts_at.in_time_zone(zone).strftime('%-l:%M %p')}",
                            body: details.join(" · "), path: routes.task_path(task), tag: "reminder-#{task.id}",
                            ttl: (task.starts_at - now).to_i)
  rescue StandardError => error
    Rails.logger.warn("Event reminder failed for task #{task.id}: #{error.class}: #{error.message}")
  end

  def send_digests(now)
    Household.includes(:users).find_each do |household|
      local = now.in_time_zone(household.zone || Time.zone_default)
      household.users.each do |person|
        next unless person.digest_hour == local.hour

        digest(household, person, local)
      end
    end
  end

  def digest(household, person, local)
    preference = person.notification_preference("todo_digest")
    return unless preference.push || preference.email

    today = local.to_date
    todos = Task.for_household(household).for_person(person).open.untimed.where(due_on: today).order(:created_at).to_a
    return if todos.empty?
    return unless ReminderSent.claim(user_id: person.id, household_id: household.id, task_id: nil, kind: "digest",
                                     occurrence_starts_at: local.beginning_of_day)

    titles = todos.map { |todo| todo.title_for(person) }
    Notifier.notify(person, category: "todo_digest", household: household, now: local,
                            title: "#{todos.size} #{'to-do'.pluralize(todos.size)} for today",
                            body: titles.to_sentence, path: routes.tasks_path, tag: "digest-#{today.iso8601}",
                            ttl: 12.hours.to_i)
  rescue StandardError => error
    Rails.logger.warn("To-do digest failed for user #{person.id}: #{error.class}: #{error.message}")
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
