# Until the first account exists, /setup asks for a one-time code so that
# whoever finds a fresh server first can't claim it. Print the code where the
# person who started the server will look: the server's own output.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) && AppSettings.setup_code_required?

  begin
    next if User.exists?
  rescue ActiveRecord::ActiveRecordError
    next # database not ready; db:prepare runs before the server in Docker
  end

  $stdout.puts <<~BANNER

    ================================================================
      Family Status is ready to set up.
      Open /setup in your browser and enter this setup code:

          #{AppSettings.setup_code}

      Print it again any time with: bin/rails setup:code
    ================================================================

  BANNER
  $stdout.flush
end
