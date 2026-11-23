# Web Push on the Ruby standard library only (OpenSSL + Net::HTTP):
#
#   WebPush::Encryption  RFC 8291 message encryption (aes128gcm, RFC 8188)
#   WebPush::Vapid       RFC 8292 application server identification (ES256 JWT)
#   WebPush::Client      RFC 8030 delivery to a browser's push service
#
# Endpoints are only ever posted to if they're https on a known push
# service's host (ALLOWED_HOSTS): a subscription is data a browser sent us,
# and an allowlist can't be raced the way resolve-then-check DNS can.
require "uri"

module WebPush
  class Error < StandardError; end

  # Exact hosts, and suffixes (leading dot) for services with many hosts.
  ALLOWED_HOSTS = [
    "fcm.googleapis.com",                 # Chrome, Edge on Android, Samsung, Opera, Brave
    ".push.apple.com",                    # Safari (web.push.apple.com)
    ".notify.windows.com",                # Edge on Windows (wns2-*.notify.windows.com)
    "updates.push.services.mozilla.com",  # Firefox
    "push.services.mozilla.com"
  ].freeze

  module_function

  def allowed_endpoint?(endpoint)
    uri = URI.parse(endpoint.to_s)
    return false unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?

    host = uri.host.to_s.downcase
    ALLOWED_HOSTS.any? { |allowed| allowed.start_with?(".") ? host.end_with?(allowed) && host.length > allowed.length : host == allowed }
  rescue URI::InvalidURIError
    false
  end

  module Base64Url
    module_function

    def encode(bytes)
      [bytes].pack("m0").tr("+/", "-_").delete("=")
    end

    def decode(text)
      text = text.to_s.tr("-_", "+/")
      raise Error, "malformed base64url" unless text.match?(%r{\A[A-Za-z0-9+/]*={0,2}\z})

      text += "=" * ((4 - text.length % 4) % 4)
      text.unpack1("m0")
    rescue ArgumentError
      raise Error, "malformed base64url"
    end
  end
end
