class Setting < ApplicationRecord
  encrypts :value, deterministic: false

  validates :key, presence: true, uniqueness: true

  # Reads a setting by key, returning nil when absent.
  def self.get(key)
    find_by(key: key.to_s)&.value
  end

  # Writes a setting by key, creating or updating the row.
  def self.set(key, value)
    where(key: key.to_s).first_or_initialize.update!(value: value)
  end
end