class Setting < ApplicationRecord
  encrypts :value, deterministic: false

  validates :key, presence: true, uniqueness: true

  # Reads a setting by key, returning nil when absent. All rows are loaded
  # once per request (there are only a handful), since the layout, mailers
  # and AppSettings each ask for several keys.
  def self.get(key)
    all_by_key[key.to_s]
  end

  # Writes a setting by key, creating or updating the row.
  def self.set(key, value)
    where(key: key.to_s).first_or_initialize.update!(value: value)
    Current.settings = nil
  end

  def self.all_by_key
    Current.settings ||= all.to_h { |setting| [setting.key, setting.readable_value] }
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    {} # no database or table yet (first boot, asset precompile)
  end

  # A value encrypted under different keys (a restored backup without its
  # master key, say) reads as blank instead of taking every page down.
  def readable_value
    value
  rescue ActiveRecord::Encryption::Errors::Base => error
    Rails.logger.warn("Setting #{key} could not be decrypted (#{error.class}); treating it as blank")
    nil
  end
end
