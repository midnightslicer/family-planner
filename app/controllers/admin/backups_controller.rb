module Admin
  # Admin > Backup: download the whole app (every household, account, photo)
  # as one zip (Backup), to restore on a fresh server's setup page; or
  # restore one here, over everything (typed RESTORE to confirm, and a
  # backup of what's here is saved first).
  class BackupsController < BaseController
    CONFIRM = "RESTORE".freeze

    rate_limit to: 5, within: 5.minutes, only: :restore, with: -> {
      redirect_to admin_backup_path, alert: "Too many restores. Wait a few minutes and try again.", status: :see_other
    }
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

    # POST /admin/backup/restore: replaces this server's whole database and
    # photos with the zip's. Then you sign in again: the accounts are the
    # backup's now.
    def restore
      file = params[:backup]
      unless file.respond_to?(:path)
        redirect_to admin_backup_path, alert: "Choose a backup zip to restore.", status: :see_other
        return
      end
      unless params[:confirm].to_s.strip.upcase == CONFIRM
        redirect_to admin_backup_path, alert: "Type #{CONFIRM} to confirm. Nothing was changed.", status: :see_other
        return
      end

      result = Backup.restore(file.path, replace: true)
      sign_out(:user)
      reset_session
      redirect_to new_user_session_path, notice: result.summary, status: :see_other
    rescue Backup::Invalid => error
      redirect_to admin_backup_path, alert: "#{error.message} Nothing was changed.", status: :see_other
    end
  end
end
