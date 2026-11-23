namespace :push do
  desc "Print the VAPID public key browsers subscribe against (generates the key pair on first use)"
  task keys: :environment do
    if (public_key = PushKeys.public_key)
      puts "VAPID public key: #{public_key}"
      puts "Subject:          #{PushKeys.subject}"
      puts "Private key:      #{ENV['VAPID_PRIVATE_KEY'].present? ? 'VAPID_PRIVATE_KEY' : PushKeys.path}"
    else
      abort "Push notifications are off: no usable VAPID key. Check VAPID_PRIVATE_KEY or that #{PushKeys.path} is writable."
    end
  end
end
