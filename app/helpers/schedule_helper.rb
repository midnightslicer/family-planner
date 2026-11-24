# Times, days and availability as the schedule and person cards say them.
module ScheduleHelper
  # [label, icon, css] for each availability: how reachable someone is.
  # These three are the only statuses a person ever shows.
  AVAILABILITY = {
    "free" => ["Free", :sun, "avail-free"],
    "text" => ["Text only", :message, "avail-text"],
    "busy" => ["Do not disturb", :bell_off, "avail-busy"]
  }.freeze

  # Longer wording for the form's choices.
  AVAILABILITY_HINTS = {
    "free" => "Call or text any time",
    "text" => "Busy, but a text is fine",
    "busy" => "Don't call or text"
  }.freeze

  # What says how reachable someone is now, from their member status: a
  # status they set by hand (StatusUpdate) wins over whatever they're on.
  def reachability(status)
    status[:set] || status[:current]
  end

  # Someone's status chip from their member status: what they set by hand,
  # else what they're on, else Free.
  def reach_chip(status)
    availability_chip(reachability(status) || "free")
  end

  # The chip for a task, a StatusUpdate, or a bare availability ("free").
  def availability_chip(task, prefix: nil)
    label, icon_name, css = AVAILABILITY.fetch(task.respond_to?(:availability) ? task.availability : task.to_s)
    tag.span(safe_join([icon(icon_name), [prefix, label].compact.join(" ")]), class: "status-chip #{css}")
  end

  # "9 AM", "9:30 AM".
  def clock(time)
    time.strftime(time.min.zero? ? "%-l %p" : "%-l:%M %p")
  end

  # "Today", "Tomorrow", "Sat", or "Sat, Dec 6" further out.
  def day_name(date, today = Date.current)
    if date == today then "Today"
    elsif date == today + 1 then "Tomorrow"
    elsif date < today + 7 && date > today then date.strftime("%a")
    else date.strftime("%a, %b %-d")
    end
  end

  # "9 – 10 AM", "11:30 AM – 1 PM", with the day when it isn't today.
  def time_range(task, with_day: :unless_today)
    from = task.starts_at
    to = task.finishes_at
    range = from.strftime("%p") == to.strftime("%p") && from.to_date == to.to_date ?
      "#{clock(from).sub(/ [AP]M\z/, '')} – #{clock(to)}" : "#{clock(from)} – #{clock(to)}"
    show_day = with_day == :always || (with_day == :unless_today && from.to_date != Date.current)
    show_day ? "#{day_name(from.to_date)} #{range}" : range
  end

  # "Meeting · until 3 PM · Town": what's on. A private item reads "Busy ·
  # until 3 PM" to anyone but its people; with no viewer (person cards,
  # which also go to the wall) it always does.
  def now_line(task, viewer = nil)
    visible = task.visible_to?(viewer)
    parts = [task.title_for(viewer)]
    parts << "until #{clock(task.finishes_at)}" if task.timed?
    parts << task.place_name if visible && task.place_name
    parts.join(" · ")
  end

  # "Church · 10 AM" or "Church · Sun 10 AM".
  def next_line(task, viewer = nil)
    when_text = task.starts_at.to_date == Date.current ? clock(task.starts_at) : "#{day_name(task.starts_at.to_date)} #{clock(task.starts_at)}"
    [task.title_for(viewer), when_text].join(" · ")
  end
end
