class User < ApplicationRecord
  # No :registerable: accounts come only from the setup wizard (first admin)
  # and invitations, so there is no public sign-up route at all.
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  RECOVERY_CODE_COUNT = 10
  PALETTE = %w[
    #6366f1 #8b5cf6 #ec4899 #f43f5e #ef4444 #f97316 #f59e0b #eab308
    #84cc16 #22c55e #10b981 #14b8a6 #06b6d4 #0ea5e9 #3b82f6 #64748b
    #a8a29e #d97706 #9333ea #0f766e
  ].freeze

  include SmallPhoto

  encrypts :otp_secret
  small_photo :avatar
  serialize :otp_recovery_codes, coder: JSON

  validates :display_name, presence: true, length: { maximum: 60 }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a 6-digit hex color" }
  validate :birthday_not_in_future
  validates :work_availability, inclusion: { in: %w[free text busy] }

  # Notification settings (the Notifications page).
  REMINDER_LEADS = [5, 15, 30, 60].freeze
  DIGEST_HOURS = (0..23).freeze
  QUIET_STEP = 30 # quiet hours start and end on the hour or half hour
  validates :reminder_lead_minutes, inclusion: { in: REMINDER_LEADS }
  validates :digest_hour, inclusion: { in: DIGEST_HOURS }
  validates :quiet_hours_start, :quiet_hours_end,
            inclusion: { in: (0...24 * 60).step(QUIET_STEP).to_a, message: "isn't a time" }, allow_nil: true
  validate :quiet_hours_complete

  has_many :household_memberships, dependent: :destroy
  has_many :households, through: :household_memberships
  has_many :passkeys, dependent: :destroy
  has_many :push_subscriptions, dependent: :delete_all
  has_many :notification_preferences, dependent: :delete_all
  has_many :reminders_sent, class_name: "ReminderSent", dependent: :delete_all
  has_many :task_assignments, dependent: :delete_all
  has_many :residences, dependent: :delete_all
  has_many :status_updates, dependent: :delete_all
  has_many :work_schedule_versions, dependent: :delete_all
  has_many :finished_tasks, class_name: "Task", foreign_key: :finished_by_id, dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: :created_by_id, dependent: :nullify
  has_many :invitations_sent, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :location_reports, as: :subject, dependent: :delete_all
  has_many :location_reports_made, class_name: "LocationReport", foreign_key: :reported_by_id, dependent: :nullify
  has_many :feedings_given, class_name: "Feeding", foreign_key: :fed_by_id, dependent: :nullify
  has_many :pet_subscriptions, dependent: :delete_all
  has_many :work_shifts, -> { order(:weekday) }, dependent: :delete_all
  has_many :days_off, -> { order(:starts_on) }, class_name: "DayOff", dependent: :delete_all
  has_many :pets_added, class_name: "Pet", foreign_key: :created_by_id, dependent: :nullify
  has_many :locations_added, class_name: "Location", foreign_key: :created_by_id, dependent: :nullify

  # Set when an account is created with a passkey instead of a password.
  attr_accessor :signing_up_with_passkey

  # The colour picker's "Custom color" box. It has its own name so it can't
  # override the palette swatch (both used to post user[color], and the box,
  # prefilled with the old colour, came last and won). Filled in, it wins.
  attr_accessor :custom_color

  before_validation :apply_custom_color
  before_validation :normalize_color
  # A new password also stops every "remember me" cookie (Devise's
  # remember_token outlives it otherwise); sessions end with the salt.
  after_update :forget_remembered_devices, if: :saved_change_to_encrypted_password?

  # A colour from the palette nobody in the household is using yet, so new
  # people get a distinct card without having to pick one.
  def self.suggested_color(household = nil)
    taken = household ? household.users.pluck(:color) : []
    (PALETTE - taken).sample || PALETTE.sample
  end

  # The person card for this user, re-rendered on every board they're on
  # (after a name, colour or photo change).
  def broadcast_card
    households.each { |household| household.broadcast_member_cards([id]) }
  end

  def works?
    work_shifts.any?
  end

  # ---- Notifications ----

  # This person's choice for a kind of update, saved or the default.
  def notification_preference(category)
    category = NotificationPreference.category(category).key
    notification_preferences.find { |preference| preference.category == category } ||
      NotificationPreference.new(user: self, category: category)
  end

  def notifications_paused?(now = Time.current)
    notifications_paused_until.present? && notifications_paused_until > now
  end

  def quiet_hours?
    quiet_hours_start.present? && quiet_hours_end.present? && quiet_hours_start != quiet_hours_end
  end

  # Whether `time` falls in quiet hours, read on `time`'s own clock (pass it
  # in the household's zone). 22:00-07:00 runs across midnight.
  def quiet_at?(time)
    return false unless quiet_hours?

    minute = time.hour * 60 + time.min
    if quiet_hours_start < quiet_hours_end
      minute >= quiet_hours_start && minute < quiet_hours_end
    else
      minute >= quiet_hours_start || minute < quiet_hours_end
    end
  end

  def day_off_on(date = Date.current)
    days_off.find { |off| off.covers?(date) }
  end

  # The house they live in, in this household.
  def home_in(household)
    household_memberships.find_by(household: household)&.home
  end

  # In memory when the households are already loaded, else one query.
  def member_of?(household)
    households.include?(household)
  end

  def password_set?
    encrypted_password.present?
  end

  # Ways left to sign in; used to stop someone removing their last one.
  def sign_in_methods_count
    (password_set? ? 1 : 0) + passkeys.count
  end

  def webauthn_handle
    self.webauthn_id ||= WebAuthn::Base64Url.encode(SecureRandom.random_bytes(32))
    WebAuthn::Base64Url.decode(webauthn_id)
  end

  # ---- Two-factor (TOTP) ----

  def two_factor_enabled?
    otp_enabled_at.present? && otp_secret.present?
  end

  # Turns 2FA on once the person proves their app produces the right code.
  # Returns the plain recovery codes (shown once) or nil if the code is wrong.
  def enable_two_factor!(secret, code)
    step = Totp.verify(secret, code) or return nil

    codes = new_recovery_codes
    update!(otp_secret: secret, otp_enabled_at: Time.current, otp_last_used_step: step,
            otp_recovery_codes: codes.map { |c| recovery_digest(c) })
    codes
  end

  def disable_two_factor!
    update!(otp_secret: nil, otp_enabled_at: nil, otp_last_used_step: nil, otp_recovery_codes: nil)
  end

  # Accepts a current authenticator code or an unused recovery code.
  def verify_second_factor!(code)
    return false unless two_factor_enabled?

    verify_otp!(code) || consume_recovery_code!(code)
  end

  def recovery_codes_remaining
    Array(otp_recovery_codes).size
  end

  def regenerate_recovery_codes!
    codes = new_recovery_codes
    update!(otp_recovery_codes: codes.map { |c| recovery_digest(c) })
    codes
  end

  # Lets an admin help someone who lost their phone: clears 2FA and passkeys
  # so they can get back in with a password reset, and signs them out
  # everywhere, the lost phone included.
  def reset_sign_in_security!
    transaction do
      passkeys.destroy_all
      disable_two_factor!
      sign_out_everywhere!
    end
  end

  # Every session and "remember me" cookie stops working.
  def sign_out_everywhere!
    update_columns(session_token: SecureRandom.hex(16), remember_token: nil, remember_created_at: nil)
  end

  # Devise keeps this in each session and checks it on every request. It's
  # the password hash's salt, which a passkey-only account doesn't have, so
  # session_token is added: changing either ends every session.
  def authenticatable_salt
    "#{super}#{session_token}"
  end

  # A password reset link an admin can pass on by hand, for boards without
  # email (or for someone whose email isn't arriving). Same token and expiry
  # as the emailed link.
  def generate_password_reset_token!
    set_reset_password_token
  end

  protected

  # Devise mail goes through the job queue: a slow or unconfigured SMTP
  # server shouldn't turn "forgot password" into an error page.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  # Devise :validatable hook. Passkey sign-ups have no password to validate.
  def password_required?
    return false if signing_up_with_passkey && password.blank?

    super
  end

  private

  def verify_otp!(code)
    step = Totp.verify(otp_secret, code, after: otp_last_used_step) or return false

    # Conditional update so two requests can't both spend the same code.
    User.where(id: id).where("otp_last_used_step IS NULL OR otp_last_used_step < ?", step)
        .update_all(otp_last_used_step: step) == 1
  end

  def consume_recovery_code!(code)
    digest = recovery_digest(code)
    remaining = Array(otp_recovery_codes)
    return false unless remaining.any? { |stored| ActiveSupport::SecurityUtils.secure_compare(stored, digest) }

    update!(otp_recovery_codes: remaining - [digest])
    true
  end

  def new_recovery_codes
    Array.new(RECOVERY_CODE_COUNT) do
      Totp.base32_encode(SecureRandom.random_bytes(7))[0, 10].downcase.insert(5, "-")
    end
  end

  def recovery_digest(code)
    normalized = code.to_s.downcase.gsub(/[^a-z2-7]/, "")
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "recovery-code:#{normalized}")
  end

  def forget_remembered_devices
    update_columns(remember_token: nil, remember_created_at: nil)
  end

  def apply_custom_color
    self.color = custom_color if custom_color.present?
  end

  def quiet_hours_complete
    return if quiet_hours_start.nil? == quiet_hours_end.nil?

    errors.add(:base, "Quiet hours need both a start and an end.")
  end

  def birthday_not_in_future
    errors.add(:birthday, "can't be in the future") if birthday && birthday > Date.current
  end

  def normalize_color
    self.color = color.to_s.strip.downcase.presence || PALETTE.first
    self.color = "##{color}" unless color.start_with?("#")
  end
end
