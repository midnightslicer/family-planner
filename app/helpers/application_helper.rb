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

  # Curated palette for the color picker partial.
  PALETTE = User::PALETTE

  # One or two letters for the avatar disc on a person card.
  def initials(name)
    parts = name.to_s.split(/[\s_-]+/).reject(&:empty?)
    return "?" if parts.empty?

    parts.first(2).map { |part| part[0] }.join.upcase
  end

  def two_factor_status(user)
    user.two_factor_enabled? ? "On" : "Off"
  end
end
