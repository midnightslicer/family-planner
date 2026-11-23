# The token in an email's "Unsubscribe from these emails" link: who and
# which kind of update, signed so it can't be forged or edited. It works
# signed out and doesn't expire (old emails should still unsubscribe), and
# all it can ever do is turn that one kind of email off.
module NotificationUnsubscribe
  module_function

  def token_for(user, category)
    verifier.generate([user.id, NotificationPreference.category(category).key], purpose: :unsubscribe)
  end

  # [user, category key], or nil for a bad token or a deleted account.
  def resolve(token)
    user_id, category = verifier.verified(token.to_s, purpose: :unsubscribe)
    return unless NotificationPreference::CATEGORIES.key?(category)

    user = User.find_by(id: user_id) or return
    [user, category]
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def unsubscribe!(user, category)
    preference = user.notification_preferences.find_or_initialize_by(category: category)
    preference.update!(email: false)
  end

  def verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("notification unsubscribe", 32),
                                       digest: "SHA256", serializer: JSON, url_safe: true)
  end
end
