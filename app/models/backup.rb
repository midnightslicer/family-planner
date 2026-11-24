# The whole app in one zip, and back: Admin > Backup downloads one, the
# setup page of a fresh server restores one, and `bin/rails backup:create`
# / `backup:restore` do the same from a shell.
#
# The zip holds
#   manifest.json     format, app schema version, when, and counts
#   database.sqlite3  a consistent copy of the primary database (SQLite's
#                     backup API, so it's safe while the app is running)
#   files/<key>       every Active Storage file (photos), by blob key
#
# No secret leaves in the clear: the encrypted columns (SMTP password, TOTP
# secrets, push subscription keys) stay encrypted under this server's keys
# (from SECRET_KEY_BASE), and the push signing key (storage/.vapid_key)
# isn't in the zip at all. Restored onto a server with the same
# SECRET_KEY_BASE they all still read; anywhere else whatever can't be read
# is cleared: two-step verification is turned off for those people (they
# set it up again), the SMTP password is blank (Admin > Settings), and push
# subscriptions are always dropped (browsers subscribe again on their own).
# Password hashes (bcrypt) and passkey public keys come along, so everyone
# signs in as before; passkeys only on the same domain, as they're bound to
# it. Still everything the board knows: keep the zip as safe as the server.
#
# Restore only goes onto a server with no accounts yet (a fresh install):
# it replaces the whole database, runs any migrations newer than the
# backup, clears what it can't read and puts the files back. Only the named
# entries are read, so nothing in the zip is written to a path it chooses.
#
#   Backup.write("family.zip")             # => "family.zip"
#   Backup.restore("family.zip")           # => Backup::Result
class Backup
  FORMAT = 1
  MANIFEST = "manifest.json".freeze
  DATABASE = "database.sqlite3".freeze
  FILES = "files/".freeze
  # Generous for a family's photos, small enough that a bad upload can't
  # fill the disk.
  MAX_ENTRY = 500.megabytes
  MAX_TOTAL = 4.gigabytes

  class Invalid < StandardError; end

  Result = Struct.new(:people, :households, :files, :missing_files, :two_factor_reset, :smtp_password_cleared, keyword_init: true)

  class << self
    def write(path)
      Dir.mktmpdir("backup") do |dir|
        database = File.join(dir, DATABASE)
        copy_database(from: ApplicationRecord.connection.raw_connection, to: database)
        keys = SQLite3::Database.open(database) { |db| db.execute("SELECT key FROM active_storage_blobs").flatten }

        Zip::OutputStream.open(path) do |zip|
          zip.put_next_entry(MANIFEST)
          zip.write(JSON.pretty_generate(manifest(database)))
          zip.put_next_entry(DATABASE)
          File.open(database, "rb") { |file| copy(file, zip) }
          keys.each do |key|
            next unless ActiveStorage::Blob.service.exist?(key)

            zip.put_next_entry(FILES + key)
            ActiveStorage::Blob.service.download(key) { |chunk| zip.write(chunk) }
          end
        end
      end
      path
    end

    # A name for a download or a file on disk: "the-smiths-backup-2026-11-24-1335.zip".
    def filename(time = Time.current)
      "#{AppSettings.app_name.parameterize.presence || 'family-status'}-backup-#{time.strftime('%Y-%m-%d-%H%M')}.zip"
    end

    def restore(path)
      raise Invalid, "This server already has accounts. Restore only goes onto a fresh install." if User.exists?

      Zip::File.open(path) do |zip|
        check_size(zip)
        manifest = read_json(zip, MANIFEST)
        raise Invalid, "That backup is from a newer version of the app (format #{manifest['format']}). Update this server first." if manifest["format"].to_i > FORMAT
        raise Invalid, "That zip isn't a backup from this app." unless manifest["format"].to_i == FORMAT

        Dir.mktmpdir("restore") do |dir|
          database = extract(zip, DATABASE, dir)
          check_database(database)
          copy_database(from: database, to: ApplicationRecord.connection.raw_connection)
        end
        reload_schema
        ApplicationRecord.connection_pool.migration_context.migrate
        reload_schema
        two_factor_reset, smtp_cleared = clear_unreadable_secrets
        files, missing = restore_files(zip)
        Result.new(people: User.count, households: Household.count, files: files, missing_files: missing,
                   two_factor_reset: two_factor_reset, smtp_password_cleared: smtp_cleared)
      end
    rescue Zip::Error, JSON::ParserError, SQLite3::Exception => error
      raise Invalid, "That file isn't a backup this app can read (#{error.message.truncate(120)})."
    end

    private

    def manifest(database)
      versions = SQLite3::Database.open(database) { |db| db.execute("SELECT version FROM schema_migrations").flatten }
      {
        format: FORMAT,
        app: AppSettings.app_name,
        created_at: Time.current.iso8601,
        schema_version: versions.map(&:to_i).max,
        people: User.count,
        households: Household.count,
        files: ActiveStorage::Blob.count
      }
    end

    # Encrypted values from a server with another SECRET_KEY_BASE can't be
    # read here: turn off two-step for whoever's secret that is, and drop
    # unreadable settings. Push subscriptions go regardless, since this
    # server signs pushes with its own key. Returns [two-step resets,
    # whether the SMTP password went].
    def clear_unreadable_secrets
      PushSubscription.delete_all
      unreadable = ->(record, name) do
        record.public_send(name)
        false
      rescue ActiveRecord::Encryption::Errors::Base
        true
      end
      reset = User.where.not(otp_secret: nil).select { |user| unreadable.(user, :otp_secret) }
      reset.each do |user|
        user.update_columns(otp_secret: nil, otp_enabled_at: nil, otp_last_used_step: nil, otp_recovery_codes: nil)
      end
      lost = Setting.all.select { |setting| unreadable.(setting, :value) }
      Setting.where(id: lost.map(&:id)).delete_all
      Current.settings = nil
      [reset.size, lost.any? { |setting| setting.key == "smtp_password" }]
    end

    def restore_files(zip)
      restored = missing = 0
      ActiveStorage::Blob.find_each do |blob|
        entry = zip.find_entry(FILES + blob.key)
        if entry.nil? || entry.directory?
          missing += 1
          next
        end
        # The checksum check makes a damaged file fail here, not on the page.
        entry.get_input_stream { |io| ActiveStorage::Blob.service.upload(blob.key, io, checksum: blob.checksum) }
        restored += 1
      rescue ActiveStorage::IntegrityError
        missing += 1
      end
      [restored, missing]
    end

    # SQLite's online backup: page by page, consistent, works on a live
    # database. Either side may be a path or an open connection.
    def copy_database(from:, to:)
      source = from.is_a?(String) ? SQLite3::Database.new(from, readonly: true) : from
      target = to.is_a?(String) ? SQLite3::Database.new(to) : to
      backup = SQLite3::Backup.new(target, "main", source, "main")
      backup.step(-1)
      backup.finish
    ensure
      source.close if from.is_a?(String) && source
      target.close if to.is_a?(String) && target
    end

    # The uploaded database must be sound and look like ours, and not be from
    # a newer app than this one (its tables wouldn't match this code).
    def check_database(path)
      SQLite3::Database.open(path, readonly: true) do |db|
        raise Invalid, "The database in that backup is damaged." unless db.get_first_value("PRAGMA integrity_check") == "ok"

        tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
        missing = %w[schema_migrations users households active_storage_blobs] - tables
        raise Invalid, "That backup's database is missing #{missing.to_sentence}." if missing.any?

        known = ApplicationRecord.connection_pool.migration_context.migrations.map(&:version)
        newer = db.execute("SELECT version FROM schema_migrations").flatten.map(&:to_i) - known
        raise Invalid, "That backup is from a newer version of the app. Update this server first, then restore." if newer.any?
      end
    end

    def reload_schema
      ApplicationRecord.connection.schema_cache.clear!
      ApplicationRecord.descendants.each(&:reset_column_information)
      ActiveStorage::Blob.reset_column_information
    end

    def check_size(zip)
      total = 0
      zip.each do |entry|
        raise Invalid, "#{entry.name} in that backup is too big." if entry.size > MAX_ENTRY

        total += entry.size
      end
      raise Invalid, "That backup is too big to restore here." if total > MAX_TOTAL
    end

    def read_json(zip, name)
      entry = zip.find_entry(name) or raise Invalid, "That zip isn't a backup from this app (no #{name})."
      JSON.parse(entry.get_input_stream(&:read))
    end

    def extract(zip, name, dir)
      entry = zip.find_entry(name) or raise Invalid, "That backup has no database."
      path = File.join(dir, name)
      File.open(path, "wb") { |file| entry.get_input_stream { |io| copy(io, file) } }
      path
    end

    def copy(from, to)
      while (chunk = from.read(64.kilobytes))
        to.write(chunk)
      end
    end
  end
end
