# Pets, locations and the bits of people's profiles that go with them.
module PetsHelper
  LOCATION_ICONS = { "house" => :house, "yard" => :trees, "pasture" => :fence, "pool" => :waves, "other" => :map_pin }.freeze

  OFF_PROPERTY = "Off property".freeze

  def location_icon(location)
    icon(LOCATION_ICONS.fetch(location&.kind, :map_pin))
  end

  def location_kind_label(kind)
    kind.humanize
  end

  # The square picture for a location: its photo, else its kind's icon.
  def location_picture(location)
    tag.span(location_picture_content(location), class: "place-photo", aria: { hidden: true })
  end

  def location_picture_content(location)
    location.photo_saved? ? photo_tag(location.photo) : location_icon(location)
  end

  # "Red Brick House · Outside · Penned up", "Back yard", "Off property".
  def place_label(report)
    return "Not reported yet" unless report

    [ report.location&.name || OFF_PROPERTY, report.spot&.capitalize, ("Penned up" if report.penned?) ].compact.join(" · ")
  end

  # What goes inside a pet's .person-avatar disc: its photo, else a paw.
  def pet_avatar_content(pet)
    pet.photo_saved? ? photo_tag(pet.photo) : icon(:paw)
  end

  # Pets have no colour of their own; their discs use the accent.
  PET_DISC_STYLE = "--user-color: var(--accent); --user-fg: var(--accent-fg)".freeze

  # "3 years", "1 year, 4 months", "7 months", "5 weeks", "newborn".
  def age_in_words(birthday, today = Date.current)
    return if birthday.nil? || birthday > today

    months = (today.year * 12 + today.month) - (birthday.year * 12 + birthday.month)
    months -= 1 if today.day < birthday.day
    if months >= 24 then pluralize(months / 12, "year")
    elsif months >= 12 then [ "1 year", (pluralize(months - 12, "month") if months > 12) ].compact.join(", ")
    elsif months >= 1 then pluralize(months, "month")
    elsif (weeks = (today - birthday).to_i / 7).positive? then pluralize(weeks, "week")
    else "newborn"
    end
  end

  def birthday_today?(birthday, today = Date.current)
    birthday.present? && birthday.month == today.month && birthday.day == today.day
  end

  # "Mar 4" or "Mar 4, 2019" when the year is known to matter.
  def birthday_label(birthday)
    birthday.strftime("%b %-d, %Y")
  end

  # "just now", "5 min ago", "3 h ago", "yesterday 18:05", "Mar 4".
  def when_ago(time)
    return "" unless time

    seconds = Time.current - time
    if seconds < 60 then "just now"
    elsif seconds < 1.hour then "#{(seconds / 60).floor} min ago"
    elsif time.to_date == Date.current then "#{(seconds / 3600).floor} h ago"
    elsif time.to_date == Date.yesterday then "yesterday #{time.strftime('%H:%M')}"
    else time.strftime("%b %-d")
    end
  end

  def time_tag_ago(time)
    tag.time(when_ago(time), datetime: time.iso8601, title: time.strftime("%b %-d, %H:%M"))
  end

  FED_CHIPS = { fed: [ "status-completed", :check ], partly: [ "status-planned", :utensils ], hungry: [ "status-in_progress", nil ] }.freeze

  # Inside / outside / penned up, as a chip to read at a glance (the wall).
  # Penned up is filled, since it's the one someone may need to act on.
  def spot_chip(report)
    return unless report&.spot

    icon_name, text, css = if report.penned? then [ :fence, "Penned up", "is-penned" ]
    elsif report.spot == "inside" then [ :house, "Inside", "is-inside" ]
    else [ :trees, "Outside", "is-outside" ]
    end
    tag.span(safe_join([ icon(icon_name), text ]), class: "status-chip spot-chip #{css}")
  end

  # "Fed today" / "Fed 1 of 2" / "Not fed yet", with meal pips. `short`
  # (the wall, where it shares a line) drops the "today": the pips say how
  # many meals.
  def fed_chip(status, short: false)
    return unless status.tracks_meals?

    css, icon_name = FED_CHIPS.fetch(status.fed_state)
    text =
      case status.fed_state
      when :fed then short || status.meals == 1 ? "Fed today" : "All #{status.meals} meals today"
      when :partly then "Fed #{status.fed_today} of #{status.meals}"
      else short ? "Not fed yet" : "Not fed yet today"
      end
    pips = tag.span(class: "meal-pips", aria: { hidden: true }) do
      safe_join(Array.new(status.meals) { |i| tag.span(class: ("is-fed" if i < status.fed_today)) })
    end
    tag.span(safe_join([ icon_name && icon(icon_name), text, pips ].compact), class: "status-chip #{css}")
  end
end
