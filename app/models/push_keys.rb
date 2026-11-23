# The server's VAPID key pair (RFC 8292): browsers subscribe against its
# public half, and every push is signed with the private half.
#
# VAPID_PRIVATE_KEY (base64url, the raw 32-byte key the web-push libraries
# print) wins when set; VAPID_PUBLIC_KEY, if also set, must match it.
# Otherwise a key is generated on first use into storage/.vapid_key, next to
# the database and .secret_key_base, and kept there. Never in git or the
# database. Losing it invalidates every subscription; browsers resubscribe
# themselves the next time the app is opened (see push_controller.js).
module PushKeys
  mattr_accessor :path, default: Rails.root.join("storage/.vapid_key")

  LOCK = Mutex.new

  module_function

  # A WebPush::Vapid ready to sign, or nil when no key could be had.
  def vapid
    key = self.key or return nil
    WebPush::Vapid.new(key: key, subject: subject)
  end

  def available?
    key.present?
  end

  # base64url, for the browser's applicationServerKey.
  def public_key
    vapid&.public_key
  end

  def key
    LOCK.synchronize do
      return @key if defined?(@key)

      @key = load_key
    end
  end

  def reset!
    LOCK.synchronize { remove_instance_variable(:@key) if defined?(@key) }
  end

  # Who push services should contact about our pushes: the configured
  # sender address, else the public https address, else the default sender.
  def subject
    from = AppSettings.value("smtp_from")
    address = email_address(from) if from.present?
    return "mailto:#{address}" if address

    url = AppSettings.app_url.to_s
    return url if url.start_with?("https://")

    "mailto:#{email_address(AppSettings.mail_from) || 'no-reply@localhost'}"
  end

  def email_address(text)
    address = Mail::Address.new(text.to_s).address
    address if address.to_s.include?("@")
  rescue Mail::Field::ParseError
    nil
  end

  def load_key
    if ENV["VAPID_PRIVATE_KEY"].present?
      key_from_env
    else
      key_from_file
    end
  rescue WebPush::Error, OpenSSL::PKey::PKeyError, SystemCallError => error
    Rails.logger.error("Push notifications are off: no usable VAPID key (#{error.class}: #{error.message})")
    nil
  end

  def key_from_env
    key = WebPush::Vapid.key_from_private_bytes(WebPush::Base64Url.decode(ENV["VAPID_PRIVATE_KEY"].strip))
    expected = ENV["VAPID_PUBLIC_KEY"].to_s.strip
    if expected.present? && WebPush::Vapid.new(key: key, subject: "").public_key != expected
      raise WebPush::Error, "VAPID_PUBLIC_KEY doesn't match VAPID_PRIVATE_KEY"
    end
    key
  end

  # Written to a temporary file and hard-linked into place, so two processes
  # booting at once can't both write a key, or read a half-written one.
  def key_from_file
    file = Pathname(path)
    return OpenSSL::PKey.read(file.read) if file.exist? && file.size.positive?

    pem = WebPush::Vapid.generate_key.private_to_pem
    temp = file.dirname.join("#{file.basename}.#{Process.pid}.#{SecureRandom.hex(4)}")
    File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(pem) }
    begin
      File.link(temp, file)
      Rails.logger.info("Generated a VAPID key for push notifications in #{file}")
    rescue Errno::EEXIST
      pem = file.read # someone else won the race; use theirs
    ensure
      File.delete(temp)
    end
    OpenSSL::PKey.read(pem)
  end
end
