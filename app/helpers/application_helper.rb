module ApplicationHelper
  # Returns white or near-black depending on the luminance of a hex color,
  # used to keep text legible on colored accents (exposed as --user-fg).
  def contrast_color(hex)
    hex = hex.to_s.sub("#", "")
    return "#ffffff" if hex.length != 6

    r = hex[0, 2].to_i(16)
    g = hex[2, 2].to_i(16)
    b = hex[4, 2].to_i(16)
    luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
    luminance > 0.55 ? "#111827" : "#ffffff"
  rescue StandardError
    "#ffffff"
  end

  # What each task status is called on screen.
  TASK_STATUS_LABELS = {
    "planned" => "To do",
    "in_progress" => "Doing",
    "undone" => "Skipped",
    "completed" => "Done"
  }.freeze

  def task_status_label(task)
    TASK_STATUS_LABELS.fetch(task.status)
  end

  def app_name
    Setting.get("app_name").presence || "Family Status"
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    "Family Status"
  end

  # Curated palette for the color picker partial.
  PALETTE = %w[
    #6366f1 #8b5cf6 #ec4899 #f43f5e #ef4444 #f97316 #f59e0b #eab308
    #84cc16 #22c55e #10b981 #14b8a6 #06b6d4 #0ea5e9 #3b82f6 #64748b
    #a8a29e #d97706 #9333ea #0f766e
  ].freeze

  # One or two letters for the avatar disc on a person card.
  def initials(name)
    parts = name.to_s.split(/[\s_-]+/).reject(&:empty?)
    return "?" if parts.empty?

    parts.first(2).map { |part| part[0] }.join.upcase
  end
end
