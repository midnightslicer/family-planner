class Invitation < ApplicationRecord
  TOKEN_TTL = 7.days

  belongs_to :household
  belongs_to :invited_by, class_name: "User", optional: true

  # Email is optional: without one the invite is a single-use link the admin
  # can text, and the person types their own email when joining.
  normalizes :email, with: ->(email) { email.strip.downcase.presence }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create

  attr_reader :raw_token

  # Looks up an invitation by its raw token; only the SHA256 digest persists.
  def self.find_by_raw_token(raw)
    find_by(token: Digest::SHA256.hexdigest(raw.to_s))
  end

  def accepted?
    accepted_at.present?
  end

  def pending?
    !accepted? && !expired?
  end

  def expired?
    expires_at < Time.current
  end

  def status
    return "accepted" if accepted?
    return "expired" if expired?

    "pending"
  end

  # Marks the invitation accepted; refused if already used or expired. The
  # conditional update means two simultaneous joins can't both succeed.
  def accept!
    return false if accepted? || expired?

    now = Time.current
    claimed = Invitation.where(id: id, accepted_at: nil).where("expires_at > ?", now).update_all(accepted_at: now, updated_at: now)
    return false unless claimed == 1

    self.accepted_at = now
    true
  end

  def existing_user
    User.find_by(email: email) if email.present?
  end

  def open_link?
    email.blank?
  end

  # Issues a fresh raw token (stored as digest), invalidating the old link.
  def rotate_token!
    @raw_token = SecureRandom.urlsafe_base64(32)
    self.token = Digest::SHA256.hexdigest(@raw_token)
    save!
    @raw_token
  end

  private

  def generate_token
    return if token.present?

    @raw_token = SecureRandom.urlsafe_base64(32)
    self.token = Digest::SHA256.hexdigest(@raw_token)
  end

  def set_expires_at
    self.expires_at ||= TOKEN_TTL.from_now
  end
end