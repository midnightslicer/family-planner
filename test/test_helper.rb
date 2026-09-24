ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/fake_authenticator"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Integration requests go to http://www.example.com, so that's the origin
  # and RP ID a browser would use for passkeys here.
  TEST_ORIGIN = "http://www.example.com".freeze

  def new_authenticator(**options)
    FakeAuthenticator.new(rp_id: "www.example.com", origin: TEST_ORIGIN, **options)
  end

  # Adds a passkey to the signed-in account through the real endpoints.
  def register_passkey(authenticator = new_authenticator)
    post options_account_passkeys_path, as: :json
    assert_response :success
    post account_passkeys_path, params: { credential: authenticator.create(challenge: response.parsed_body["challenge"]) }, as: :json
    assert_response :success, response.body
    authenticator
  end

  def sign_in_with_passkey(authenticator)
    post user_passkey_options_path, as: :json
    assert_response :success
    authenticator.user_handle ||= WebAuthn::Base64Url.decode(Passkey.find_by!(external_id: authenticator.encoded_id).user.webauthn_id)
    post user_passkey_session_path, params: { credential: authenticator.get(challenge: response.parsed_body["challenge"]) }, as: :json
  end
end
