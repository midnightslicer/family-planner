require "test_helper"

# Backup zips (Admin > Backup) and restoring one on a fresh server's setup
# page. A restore replaces the whole database, which can't happen inside a
# test transaction: these tests commit, wipe the data to stand in for a
# fresh server, and put the fixtures back afterwards.
class BackupTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @admin = users(:admin)
    @member = users(:member)
    @dir = Dir.mktmpdir("backup-test")
    Backup.safety_dir = File.join(@dir, "safety")
  end

  teardown do
    wipe!
    ActiveRecord::FixtureSet.reset_cache # the next test loads the fixtures again
    Backup.safety_dir = nil
    FileUtils.rm_rf(@dir)
  end

  def wipe!
    connection = ActiveRecord::Base.connection
    connection.disable_referential_integrity do
      (connection.tables - %w[schema_migrations ar_internal_metadata]).each { |table| connection.execute("DELETE FROM #{connection.quote_table_name(table)}") }
    end
    Current.settings = nil
  end

  def zip_path(name = "backup.zip") = File.join(@dir, name)

  test "admins download the whole app as a zip; others can't" do
    @member.avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png")

    sign_in @member
    get admin_backup_path
    assert_response :forbidden

    sign_in @admin
    get admin_backup_path
    assert_select "button", text: /Download backup/
    post admin_backup_path
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/attachment; filename=".+-backup-\d{4}-\d\d-\d\d-\d{4}\.zip"/, response.headers["Content-Disposition"])

    File.binwrite(zip_path, response.body)
    Zip::File.open(zip_path) do |zip|
      manifest = JSON.parse(zip.read(Backup::MANIFEST))
      assert_equal Backup::FORMAT, manifest["format"]
      assert_equal User.count, manifest["people"]
      assert zip.find_entry(Backup::DATABASE)
      assert zip.find_entry("#{Backup::FILES}#{@member.avatar.blob.key}")
      assert_nil zip.find_entry("secrets.json"), "no secret leaves decrypted"
    end
  end

  test "a fresh server restores a backup from its setup page, photos and all" do
    @member.avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png")
    location = households(:smiths).locations.create!(name: "Red Barn", kind: "other")
    blob_key = @member.avatar.blob.key
    Backup.write(zip_path)
    ActiveStorage::Blob.service.delete(blob_key)
    wipe!

    post setup_unlock_path, params: { code: AppSettings.setup_code }
    post setup_restore_path, params: { backup: Rack::Test::UploadedFile.new(zip_path, "application/zip") }
    assert_redirected_to new_user_session_path
    assert_match(/Restored 2 people in 1 household/, flash[:notice])

    assert_equal 2, User.count
    assert_equal "Red Barn", Location.find(location.id).name
    assert_equal file_fixture("avatar.png").binread, User.find(@member.id).avatar.download
    assert_equal "http://www.example.com", Setting.get("app_url")

    # Set up now: the restore form is gone, and everyone signs in as before.
    get setup_path
    assert_redirected_to root_path
  end

  test "a server with other keys drops what it can't decrypt; the same keys keep it" do
    @admin.update_columns(otp_enabled_at: Time.current)
    @admin.update!(otp_secret: "JBSWY3DPEHPK3PXP")
    Setting.set("smtp_password", "hunter2")
    @member.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/backup-test", **push_keys)
    Backup.write(zip_path)

    wipe!
    Backup.restore(zip_path)
    assert_equal "JBSWY3DPEHPK3PXP", @admin.reload.otp_secret, "same SECRET_KEY_BASE: still readable"
    assert_equal "hunter2", Setting.get("smtp_password")
    assert_equal 0, PushSubscription.count, "this server signs pushes with its own key"

    wipe!
    other_server = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("another server's key")
    result = ActiveRecord::Encryption.with_encryption_context(key_provider: other_server) { Backup.restore(zip_path) }
    assert_equal 1, result.two_factor_reset
    assert result.smtp_password_cleared
    assert_nil @admin.reload.otp_secret
    assert_not @admin.two_factor_enabled?
    assert_nil Setting.get("smtp_password")
    assert_equal households(:smiths).name, Household.first.name
  end

  test "restore refuses a server that has accounts, and a newer app's backup" do
    Backup.write(zip_path)
    error = assert_raises(Backup::Invalid) { Backup.restore(zip_path) }
    assert_match(/already has accounts/, error.message)

    wipe!
    Zip::File.open(zip_path, create: false) do |zip|
      zip.get_output_stream(Backup::MANIFEST) { |io| io.write({ format: Backup::FORMAT + 1 }.to_json) }
    end
    error = assert_raises(Backup::Invalid) { Backup.restore(zip_path) }
    assert_match(/newer version/, error.message)
    assert_equal 0, User.count
  end

  test "restoring needs the setup code; the setup page then offers it and turns a bad zip away" do
    File.write(zip_path("junk.zip"), "not a zip")
    wipe!
    post setup_restore_path, params: { backup: Rack::Test::UploadedFile.new(zip_path("junk.zip"), "application/zip") }
    assert_response :forbidden

    post setup_unlock_path, params: { code: AppSettings.setup_code }
    get setup_path
    assert_select "form[action='#{setup_restore_path}'] input[type=file][name=backup]"

    post setup_restore_path, params: { backup: Rack::Test::UploadedFile.new(zip_path("junk.zip"), "application/zip") }
    assert_redirected_to setup_path
    assert_match(/isn't a backup/, flash[:alert])
    assert_equal 0, User.count
  end

  test "an admin restores over a server in use: a loud warning, typed RESTORE, and a copy of what was here first" do
    kept = households(:smiths).locations.create!(name: "Red Barn", kind: "other")
    Backup.write(zip_path)
    later = households(:smiths).locations.create!(name: "Added later", kind: "other")
    upload = -> { Rack::Test::UploadedFile.new(zip_path, "application/zip") }

    sign_in @member
    post admin_backup_restore_path, params: { backup: upload.(), confirm: "RESTORE" }
    assert_response :forbidden
    assert Location.exists?(later.id)

    sign_in @admin
    get admin_backup_path
    assert_select ".restore-over .flash-alert", text: /overwrites the whole database/
    assert_select ".restore-over form[data-turbo-confirm]"
    assert_select ".restore-over input[name=confirm][required]"

    post admin_backup_restore_path, params: { backup: upload.(), confirm: "restor" }
    assert_redirected_to admin_backup_path
    assert_match(/Type RESTORE to confirm. Nothing was changed./, flash[:alert])
    assert Location.exists?(later.id)

    post admin_backup_restore_path, params: { backup: Rack::Test::UploadedFile.new(file_fixture("avatar.png"), "image/png"), confirm: "RESTORE" }
    assert_redirected_to admin_backup_path
    assert_match(/isn't a backup.*Nothing was changed/, flash[:alert])
    assert Location.exists?(later.id)
    assert_empty Dir.glob(File.join(Backup.safety_dir, "*")), "no copy until the zip checks out"

    post admin_backup_restore_path, params: { backup: upload.(), confirm: " restore " }
    assert_redirected_to new_user_session_path
    assert_match(/Restored 2 people in 1 household.*before-restore-.+\.zip/, flash[:notice])
    assert_not Location.exists?(later.id), "what came after the backup is gone"
    assert_equal "Red Barn", Location.find(kept.id).name

    # What was here is saved, "Added later" and all.
    copy = Dir.glob(File.join(Backup.safety_dir, "before-restore-*.zip")).sole
    Zip::File.open(copy) do |zip|
      File.binwrite(File.join(@dir, "before.sqlite3"), zip.read(Backup::DATABASE))
    end
    names = SQLite3::Database.open(File.join(@dir, "before.sqlite3")) { |db| db.execute("SELECT name FROM locations").flatten }
    assert_includes names, "Added later"

    get admin_backup_path # signed out
    assert_redirected_to new_user_session_path
  end
end
