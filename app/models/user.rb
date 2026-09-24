class User < ApplicationRecord
  # No :registerable: accounts come only from the setup wizard (first admin)
  # and invitations, so there is no public sign-up route at all.
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :timeoutable

  HANDLE_FORMAT = /\A[a-z0-9_]+\z/
  RECOVERY_CODE_COUNT = 10
  PALETTE = %w[
    #6366f1 #8b5cf6 #ec4899 #f43f5e #ef4444 #f97316 #f59e0b #eab308
    #84cc16 #22c55e #10b981 #14b8a6 #06b6d4 #0ea5e9 #3b82f6 #64748b
    #a8a29e #d97706 #9333ea #0f766e
  ].freeze

  encrypts :otp_secret
  serialize :otp_recovery_codes, coder: JSON

  validates :handle, presence: true,
                     uniqueness: { case_sensitive: false },
                     format: { with: HANDLE_FORMAT, message: "may only contain lowercase letters, numbers, and underscores" }
  validates :display_name, presence: true, length: { maximum: 60 }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a 6-digit hex color" }

  has_many :household_memberships, dependent: :destroy
  has_many :households, through: :household_memberships
  has_many :passkeys, dependent: :destroy
  has_many :assigned_tasks, class_name: "Task", foreign_key: :assigned_to_id, dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: :created_by_id, dependent: :nullify
  has_many :invitations_sent, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify

  # Set when an account is created with a passkey instead of a password.
  attr_accessor :signing_up_with_passkey

  before_validation :normalize_color
  before_validation :normalize_handle
  before_validation :ensure_handle, if: -> { handle.blank? }

  # A colour from the palette nobody in the household is using yet, so new
  # people get a distinct card without having to pick one.
  def self.suggested_color(household = nil)
    taken = household ? household.users.pluck(:color) : []
    (PALETTE - taken).sample || PALETTE.sample
  end

  def member_of?(household)
    households.exists?(household.id)
  end

  def initials
    display_name.to_s.split(/\s+/).filter_map { |word| word[0]&.upcase }.take(2).join.presence || "?"
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
  # so they can get back in with a password reset.
  def reset_sign_in_security!
    transaction do
      passkeys.destroy_all
      disable_two_factor!
    end
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

  def normalize_color
    self.color = color.to_s.strip.downcase.presence || PALETTE.first
    self.color = "##{color}" unless color.start_with?("#")
  end

  def normalize_handle
    self.handle = handle.to_s.strip.downcase.presence
  end

  # Handles are derived from the display name unless someone picks one; the
  # join and setup forms don't ask for it.
  def ensure_handle
    base = display_name.to_s.downcase.gsub(/[^a-z0-9_]/, "_").squeeze("_").delete_prefix("_").delete_suffix("_")
    base = "user" if base.blank?
    base = base[0, 20]
    candidate = base
    suffix = 1
    while User.where.not(id: id).exists?(handle: candidate)
      suffix += 1
      candidate = "#{base}_#{suffix}"
    end
    self.handle = candidate
  end
end
