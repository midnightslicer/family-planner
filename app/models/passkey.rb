# A WebAuthn credential (passkey) someone registered for their account. Only
# the public key is stored; the private key never leaves their device or
# password manager.
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, :algorithm, presence: true
  validates :name, presence: true, length: { maximum: 60 }

  # A readable default name from the browser's user agent, so the list on the
  # account page says "iPhone" or "Mac" instead of a credential id.
  def self.name_from_user_agent(user_agent)
    ua = user_agent.to_s
    device =
      case ua
      when /iPhone/ then "iPhone"
      when /iPad/ then "iPad"
      when /Android/ then "Android"
      when /Macintosh|Mac OS X/ then "Mac"
      when /Windows/ then "Windows"
      when /CrOS/ then "Chromebook"
      when /Linux/ then "Linux"
      else "Passkey"
      end
    browser =
      case ua
      when /Edg\// then "Edge"
      when /Firefox\// then "Firefox"
      when /Chrome\// then "Chrome"
      when /Safari\// then "Safari"
      end
    [device, browser].compact.join(" · ")
  end

  def self.attributes_from(registration, name:)
    {
      external_id: registration.credential_id,
      public_key: registration.public_key,
      algorithm: registration.algorithm,
      sign_count: registration.sign_count,
      transports: registration.transports.join(","),
      backed_up: registration.backed_up,
      name: name.to_s.strip.first(60).presence || "Passkey"
    }
  end
end
