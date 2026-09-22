class Invitation < ApplicationRecord
  TOKEN_TTL = 7.days

  belongs_to :household
  belongs_to :invited_by, class_name: "User", optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create

  attr_reader :raw_token

  # Looks up an invitation by its raw token; only the SHA256 digest persists.
  def self.find_by_raw_token(raw)
    find_by(token: Digest::SHA256.hexdigest(raw.to_s))
  end

  def pending?
    !accepted_at && !expired?
  end

  def expired?
    expires_at < Time.current
  end

  def status
    return "accepted" if accepted_at
    return "expired" if expired?

    "pending"
  end

  # Marks the invitation accepted; refused if already used or expired.
  def accept!
    return false if accepted_at || expired?

    update!(accepted_at: Time.current)
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