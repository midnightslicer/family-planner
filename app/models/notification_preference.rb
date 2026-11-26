# One person's choice for one kind of update: push and/or email. Rows only
# exist once someone saves the Notifications page; until then (and for any
# category added later) the defaults in CATEGORIES apply.
class NotificationPreference < ApplicationRecord
  Category = Data.define(:key, :label, :hint, :push, :email)

  # Display order on the Notifications page. Email defaults are mostly off
  # because email is one message per update; "Things for me" is on so people
  # who never install the app still hear about what needs them.
  CATEGORIES = [
    Category.new("assigned", "Things for me", "New items for you, and requests that need your OK", true, true),
    Category.new("replies", "Answers to my requests", "When someone accepts or declines something you made", true, false),
    Category.new("task_updates", "Changes to my items", "An item you're on, or following up, is started, done or skipped", true, false),
    Category.new("pets", "Pets I follow", "A pet you follow is moved or fed", true, false),
    Category.new("event_reminders", "Event reminders", "An event you've said yes to is about to start", true, false),
    Category.new("todo_digest", "Today's to-dos", "One morning list of the to-dos due today", false, false)
  ].index_by(&:key).freeze

  belongs_to :user

  validates :category, inclusion: { in: CATEGORIES.keys }, uniqueness: { scope: :user_id }
  validates :push, :email, inclusion: { in: [ true, false ] }

  after_initialize :apply_defaults, if: :new_record?

  def self.category(key)
    CATEGORIES.fetch(key.to_s) { raise ArgumentError, "unknown notification category #{key.inspect}" }
  end

  # Every category in display order, saved or default, for the form.
  def self.matrix_for(user)
    CATEGORIES.each_key.map { |key| user.notification_preference(key) }
  end

  def definition
    self.class.category(category)
  end

  delegate :label, :hint, to: :definition

  private

  def apply_defaults
    return unless CATEGORIES.key?(category)

    self.push = definition.push if push.nil?
    self.email = definition.email if email.nil?
  end
end
