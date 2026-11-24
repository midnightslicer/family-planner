module Admin
  # Admin > Backup: download the whole app (every household, account, photo)
  # as one zip (Backup), to restore on a fresh server's setup page.
  class BackupsController < BaseController
    # Zips are built here and sent from here; anything older than this is
    # from an earlier download and can go.
    DIR = Rails.root.join("tmp/backups")
    KEEP_FOR = 1.hour

    def show
      @counts = { people: User.count, households: Household.count, photos: ActiveStorage::Blob.count }
    end

    def create
      FileUtils.mkdir_p(DIR)
      Dir.glob(DIR.join("*.zip")).each { |old| File.delete(old) if File.mtime(old) < KEEP_FOR.ago }
      path = DIR.join("#{SecureRandom.hex(12)}.zip").to_s
      Backup.write(path)
      send_file path, filename: Backup.filename, type: "application/zip", disposition: "attachment"
    end
  end
end
