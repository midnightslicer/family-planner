namespace :setup do
  desc "Print the one-time code the /setup page asks for on a fresh install"
  task code: :environment do
    if User.exists?
      puts "Setup is already complete; sign in at /users/sign_in."
    else
      puts AppSettings.setup_code
    end
  end
end
