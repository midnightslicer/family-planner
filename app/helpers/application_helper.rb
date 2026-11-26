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

  # One or two letters for the avatar disc on a person card.
  def initials(name)
    parts = name.to_s.split(/[\s_-]+/).reject(&:empty?)
    return "?" if parts.empty?

    parts.first(2).map { |part| part[0] }.join.upcase
  end

  # What goes inside a .person-avatar disc: their photo, else initials.
  def avatar_content(user)
    user.avatar_saved? ? photo_tag(user.avatar) : initials(user.display_name)
  end

  # A stored photo (SmallPhoto) as an <img>. The signed link is made once
  # per page however many times the same face or place shows.
  def photo_tag(attachment)
    (@photo_tags ||= {})[attachment.blob_id] ||=
      image_tag(rails_blob_path(attachment, only_path: true), alt: "", loading: "lazy", decoding: "async")
  end

  # The app's main pages, for the top nav (desktop) and the tab bar (phone):
  # [label, icon, path, current?]. Home is the brand on desktop.
  def nav_pages
    [
      [ "Home", :house, root_path, current_page?(root_path) ],
      [ "Schedule", :calendar, tasks_path, request.path.start_with?("/tasks") ],
      [ "Pets", :paw, pets_path, request.path.start_with?("/pets") ],
      [ "Locations", :map_pin, locations_path, request.path.start_with?("/locations") ]
    ]
  end
end
