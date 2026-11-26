require "test_helper"

class PushKeysTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp/storage/push_keys_test_#{Process.pid}_#{SecureRandom.hex(3)}")
    FileUtils.mkdir_p(@dir)
    @saved_path = PushKeys.path
    PushKeys.path = @dir.join(".vapid_key")
    PushKeys.reset!
  end

  teardown do
    PushKeys.path = @saved_path
    PushKeys.reset!
    FileUtils.rm_rf(@dir)
    ENV.delete("VAPID_PRIVATE_KEY")
    ENV.delete("VAPID_PUBLIC_KEY")
  end

  test "a key is generated on first use, kept private on disk, and reused" do
    public_key = PushKeys.public_key
    assert_equal 65, WebPush::Base64Url.decode(public_key).bytesize
    assert PushKeys.path.file?
    assert_equal "600", format("%o", PushKeys.path.stat.mode & 0o777)

    PushKeys.reset!
    assert_equal public_key, PushKeys.public_key
    assert_equal [ ".vapid_key" ], Dir.children(@dir), "no temporary files left behind"
  end

  test "VAPID_PRIVATE_KEY wins over the file, and a mismatched public key turns push off" do
    key = WebPush::Vapid.generate_key
    vapid = WebPush::Vapid.new(key: key, subject: "x")
    ENV["VAPID_PRIVATE_KEY"] = WebPush::Base64Url.encode(vapid.private_key_bytes)
    ENV["VAPID_PUBLIC_KEY"] = vapid.public_key
    assert_equal vapid.public_key, PushKeys.public_key
    assert_not PushKeys.path.exist?

    PushKeys.reset!
    ENV["VAPID_PUBLIC_KEY"] = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "x").public_key
    assert_nil PushKeys.vapid
    assert_not PushKeys.available?
  end

  test "an unreadable key turns push off instead of raising" do
    PushKeys.path.write("not a key")
    assert_nil PushKeys.public_key
  end

  test "the subject is the sender address, else the https address" do
    Setting.set("smtp_from", "Family Board <board@example.com>")
    assert_equal "mailto:board@example.com", PushKeys.subject
    Setting.set("smtp_from", nil)
    Setting.set("app_url", "https://status.example.com")
    assert_equal "https://status.example.com", PushKeys.subject
    Setting.set("app_url", "http://status.lan")
    assert_match(/\Amailto:no-reply@status\.lan\z/, PushKeys.subject)
  end
end
