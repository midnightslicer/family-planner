# One person on a schedule item. Someone adding it for themselves is
# `accepted`; for anyone else it's accepted automatically unless it clashes
# with what's already on their schedule, in which case it's `pending` until
# they accept or decline (see TaskAssigner). Only accepted items show on a
# person's day and card, and only they affect availability.
class TaskAssignment < ApplicationRecord
  belongs_to :task, inverse_of: :assignments
  belongs_to :user

  enum :status, { accepted: "accepted", pending: "pending", declined: "declined" }

  validates :user_id, uniqueness: { scope: :task_id }
  validate :user_in_household

  scope :active, -> { where.not(status: "declined") }

  after_commit :broadcast

  # What on `user`'s schedule the task's time clashes with: their other
  # accepted events and their work hours. Returns short labels ("Work",
  # "Dentist") as `viewer` may see them (a private event is "Busy"); empty
  # for to-dos and free slots.
  def self.conflicts_for(task, user, viewer: user)
    return [] unless task.timed?

    from, to = task.starts_at, task.finishes_at
    events = task.household.tasks.open.timed.for_person(user).where.not(id: task.id)
                 .where(starts_at: (from - 1.day)...to).to_a
                 .select { |other| other.finishes_at > from }
    places = task.household.locations.to_a
    work = (from.to_date - 1..to.to_date).filter_map { |date| WorkBlock.on(user, date, locations: places) }
                                        .select { |block| block.starts_at < to && block.finishes_at > from }
    (events.map { |event| event.title_for(viewer) } + work.map(&:title)).uniq
  end

  private

  def user_in_household
    return if task.nil? || task.household.nil? || user.nil?

    errors.add(:user, "must be in the household") unless user.member_of?(task.household)
  end

  def broadcast
    household = task&.household or return
    household.broadcast_member_cards([user_id])
    household.broadcast_refresh
  rescue StandardError => error
    Rails.logger.warn("Live update failed for assignment #{id}: #{error.class}: #{error.message}")
  end
end
