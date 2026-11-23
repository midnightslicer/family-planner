# The one way to tell someone something happened. Every notification goes
# through here:
#
#   Notifier.notify(user, category: "assigned", title: "Sam added you to Church (Sun 10 AM)",
#                   body: nil, path: "/tasks/12", household: household, tag: "task-12-3", urgent: false)
#
# - toast: an in-page notice in any tab the person has open (Turbo stream
#   on [user, :notifications]);
# - push: a SendPushJob for each device they've subscribed.
#
# `title` is the headline, `body` an optional second line. The push shows
# the household's name as its title, so someone in two households knows
# which one it's about, and its link carries ?household= so a tap switches
# to it. Callers redact private items themselves (Task#title_for).
module Notifier
  TITLE_MAX = 200
  BODY_MAX = 600
  TTL = 12.hours

  module_function

  def notify(user, category:, title:, path:, household:, tag:, body: nil, urgent: false)
    return if user.nil?

    note = Note.new(category: category.to_s, title: title.to_s.squish.truncate(TITLE_MAX), body: body.to_s.squish.truncate(BODY_MAX).presence,
                    path: link(path, household), household: household, tag: tag.to_s, urgent: urgent)
    toast(user, note)
    push(user, note)
    note
  end

  Note = Struct.new(:category, :title, :body, :path, :household, :tag, :urgent, keyword_init: true) do
    # "Sam added you to Church. It clashes with Work: accept or decline."
    def text = [title, body].compact.join(" ")
  end

  def toast(user, note)
    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "notifications", partial: "shared/notification",
      locals: { title: note.household&.name.to_s, body: note.text, tag: note.tag, path: note.path }
    )
  rescue StandardError => error
    Rails.logger.warn("Notification toast failed: #{error.class}: #{error.message}")
  end

  def push(user, note)
    subscriptions = user.push_subscriptions.pluck(:id)
    return if subscriptions.empty?

    payload = push_payload(note)
    subscriptions.each do |id|
      SendPushJob.perform_later(id, payload, ttl: TTL.to_i, urgency: note.urgent ? "high" : "normal", topic: topic(note.tag))
    end
  rescue StandardError => error
    Rails.logger.warn("Queueing pushes failed: #{error.class}: #{error.message}")
  end

  # What the service worker shows (app/views/pwa/service-worker.js.erb).
  def push_payload(note)
    JSON.generate(
      title: note.household&.name.presence || AppSettings.app_name,
      body: note.text,
      path: note.path,
      tag: note.tag,
      icon: "/icon-192.png",
      badge: "/badge-96.png"
    )
  end

  # A same-origin path that also switches to the household on open.
  def link(path, household)
    path = path.to_s
    path = "/" unless path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
    return path unless household

    "#{path}#{path.include?('?') ? '&' : '?'}household=#{household.id}"
  end

  # A newer push with the same topic replaces one still waiting on the push
  # service (a phone that's off). Topics are at most 32 URL-safe characters.
  def topic(tag)
    return if tag.blank?

    tag.match?(/\A[A-Za-z0-9_-]{1,32}\z/) ? tag : Digest::SHA256.hexdigest(tag)[0, 32]
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end
end
