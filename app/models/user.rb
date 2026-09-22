class User < ApplicationRecord
  # :registerable enables the /users/sign_up route, which is overridden to
  # render the invite-only screen — the real join path is /invitations/:token.
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :timeoutable, :registerable

  HANDLE_FORMAT = /\A[a-z0-9_]+\z/

  validates :handle, presence: true,
                     uniqueness: { case_sensitive: false },
                     format: { with: HANDLE_FORMAT, message: "may only contain lowercase letters, numbers, and underscores" }
  validates :display_name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a 6-digit hex color" }

  has_many :household_memberships, dependent: :destroy
  has_many :households, through: :household_memberships
  has_many :assigned_tasks, class_name: "Task", foreign_key: :assigned_to_id, dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: :created_by_id, dependent: :nullify
  has_many :invitations_sent, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify

  before_validation :normalize_color
  before_validation :normalize_handle
  before_save :ensure_handle, if: -> { handle.blank? }

  def member_of?(household)
    households.exists?(household.id)
  end

  def initials
    display_name.to_s.split(/\s+/).filter_map { |word| word[0]&.upcase }.take(2).join.presence || "?"
  end

  private

  def normalize_color
    self.color = color.to_s.strip.downcase.presence || "#6366f1"
    self.color = "##{color}" unless color.start_with?("#")
  end

  def normalize_handle
    self.handle = handle.to_s.strip.downcase
  end

  def ensure_handle
    base = display_name.to_s.downcase.gsub(/[^a-z0-9_]/, "_").squeeze("_").presence || "user"
    candidate = base
    suffix = 1
    while User.unscoped.exists?(handle: candidate)
      suffix += 1
      candidate = "#{base}_#{suffix}"
    end
    self.handle = candidate
  end
end