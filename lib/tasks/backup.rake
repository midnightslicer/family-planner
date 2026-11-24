# The same zip as Admin > Backup, from a shell (cron, before an upgrade),
# and restoring one onto a fresh install. See app/models/backup.rb.
namespace :backup do
  desc "Write a backup zip (default: storage/backups/<name>-backup-<time>.zip)"
  task :create, [:path] => :environment do |_, args|
    path = args[:path].presence || Rails.root.join("storage/backups", Backup.filename).to_s
    FileUtils.mkdir_p(File.dirname(path))
    Backup.write(path)
    puts "Wrote #{path} (#{ActiveSupport::NumberHelper.number_to_human_size(File.size(path))})"
  end

  desc "Restore a backup zip onto this server; only while it has no accounts"
  task :restore, [:path] => :environment do |_, args|
    path = args[:path].presence or abort "Usage: bin/rails \"backup:restore[path/to/backup.zip]\""
    result = Backup.restore(path)
    puts "Restored #{result.people} people in #{result.households} households, #{result.files} files."
    puts "#{result.missing_files} files were missing from the backup." if result.missing_files.positive?
    puts "Two-step verification was turned off for #{result.two_factor_reset} people." if result.two_factor_reset.positive?
    puts "Enter the SMTP password again in Admin > Settings." if result.smtp_password_cleared
  rescue Backup::Invalid => error
    abort error.message
  end
end
