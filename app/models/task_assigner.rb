# Puts an item on the right people's schedules when it's saved, and says
# what happened, for the flash the person saving it sees:
#
# - yourself, or anyone whose schedule is free then: accepted right away;
# - anyone with a clash (another event, work hours): pending, waiting for
#   their OK, with what it clashed with;
# - anyone who already declined stays declined (they said no);
# - anyone taken off: removed.
#
# Everyone affected but the person saving gets a notification. Moving an
# event to a new time checks again for the others on it.
class TaskAssigner
  attr_reader :task, :actor, :added, :waiting, :removed, :declined

  def initialize(task, actor:)
    @task = task
    @actor = actor
    @added = []
    @waiting = []
    @removed = []
    @declined = []
  end

  def assign(user_ids, retimed: false)
    wanted = task.household.users.where(id: Array(user_ids).compact_blank).to_a
                 .sort_by { |user| [user == actor ? 0 : 1, user.display_name] }
    existing = task.assignments.reload.index_by(&:user_id)

    gone = existing.values.reject { |assignment| wanted.any? { |user| user.id == assignment.user_id } }
    gone.each(&:destroy!)
    @removed = gone.map(&:user)

    wanted.each do |user|
      assignment = existing[user.id]
      if assignment&.declined?
        @declined << user
      elsif assignment.nil? || (retimed && user != actor)
        place(assignment || task.assignments.build(user: user), user, fresh: assignment.nil?)
      end
    end
    task.assignments.reset
    self
  end

  # "Added Church for you and Jackie. Sam has Work then, so it's waiting for Sam's OK."
  def summary
    sentences = []
    if added.any?
      names = added.map { |user| user == actor ? "you" : user.display_name }
      just_me = added == [actor] && waiting.empty? && removed.empty? && declined.empty?
      sentences << (just_me ? "Added #{task.title}." : "Added #{task.title} for #{names.to_sentence}.")
    end
    waiting.each do |user, clashes|
      sentences << "#{user.display_name} has #{clashes.to_sentence} then, so it's waiting for #{user.display_name}'s OK."
    end
    sentences << "#{declined.map(&:display_name).to_sentence} already said no to this." if declined.any?
    sentences << "Took it off #{removed.map(&:display_name).to_sentence}'s list." if removed.any?
    sentences << "Saved #{task.title}." if sentences.empty?
    sentences.join(" ")
  end

  private

  def place(assignment, user, fresh:)
    clashes = user == actor ? [] : TaskAssignment.conflicts_for(task, user)
    if clashes.empty?
      assignment.update!(status: "accepted", conflict_note: nil)
      @added << user if fresh
      notify(user, "#{actor.display_name} added you to #{task.title_for(user)}#{when_text}") if fresh
    else
      assignment.update!(status: "pending", conflict_note: "Clashes with #{clashes.to_sentence}")
      # The summary is the actor's to read: someone's private event is "Busy".
      @waiting << [user, TaskAssignment.conflicts_for(task, user, viewer: actor)]
      # Waiting on their answer: urgent, so it gets through quiet hours.
      notify(user, "#{actor.display_name} asked you to #{task.title_for(user)}#{when_text}.",
             body: "It clashes with #{clashes.to_sentence}: accept or decline on your day.", urgent: true)
    end
  end

  def when_text
    return "" unless task.timed?

    " (#{task.starts_at.strftime('%a %-l:%M %p').sub(':00', '')})"
  end

  def notify(user, title, body: nil, urgent: false)
    return if user == actor

    Notifier.notify(user, category: "assigned", title: title, body: body, urgent: urgent,
                          path: Rails.application.routes.url_helpers.task_path(task),
                          household: task.household, tag: "task-#{task.id}-#{user.id}")
  end
end
