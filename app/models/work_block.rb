# Someone's work hours on one day, built from their WorkShift (never
# stored). It answers the same questions a timed Task does, so cards,
# timelines and "who's where" treat work like any other event: real events
# during work (a meeting) take precedence.
class WorkBlock
  attr_reader :user, :starts_at, :ends_at, :place, :location

  # The block for `user` on `date`, or nil if they don't work then (no
  # shift that weekday, or a day off). `locations` is the household's
  # locations, so a work place like "Little house" links to it.
  def self.on(user, date, locations: [])
    return if user.days_off.any? { |off| off.covers?(date) }

    shift = user.work_shifts.find { |candidate| candidate.weekday == date.wday } or return
    starts_at = Time.zone.parse("#{date.iso8601} #{shift.from_time}")
    ends_at = Time.zone.parse("#{date.iso8601} #{shift.until_time}")
    ends_at += 1.day if ends_at <= starts_at
    location = shift.place && locations.find { |candidate| candidate.name.casecmp?(shift.place) }
    new(user, starts_at, ends_at, shift.place, location)
  end

  # The block on now, counting a night shift that started yesterday.
  def self.current(user, now = Time.current, locations: [])
    [now.to_date, now.to_date - 1].filter_map { |date| on(user, date, locations: locations) }
                                  .find { |block| block.happening_at?(now) }
  end

  # The next block to start, within a week.
  def self.upcoming(user, now = Time.current, locations: [])
    (0..7).lazy.filter_map { |offset| on(user, now.to_date + offset, locations: locations) }
          .find { |block| block.starts_at > now }
  end

  def initialize(user, starts_at, ends_at, place, location)
    @user, @starts_at, @ends_at, @place, @location = user, starts_at, ends_at, place, location
  end

  def title = "Work"
  def title_for(_viewer) = title
  def visible_to?(_viewer) = true
  def private? = false
  def timed? = true
  def open? = true
  def planned? = true
  def in_progress? = false
  def work? = true
  def finishes_at = ends_at
  def availability = user.work_availability
  def availability_free? = availability == "free"
  def place_name = location&.name || place

  def happening_at?(time = Time.current)
    starts_at <= time && time < ends_at
  end

  def past?(time = Time.current)
    ends_at <= time
  end

  def whereabouts(time = Time.current)
    location if happening_at?(time)
  end
end
