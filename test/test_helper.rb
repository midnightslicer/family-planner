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

# The VAPID key lives in tmp, not storage/, under test (generated once and
# shared by the parallel workers; PushKeys handles the race).
PushKeys.path = Rails.root.join("tmp/storage/.vapid_key")

# A stand-in for the push services: records each request PushSubscription
# would have sent and answers with the given status code.
class FakePushService
  attr_reader :requests

  def initialize(code = "201")
    @code = code
    @requests = []
  end

  def respond_with(code)
    @code = code
  end

  def call(uri, request)
    @requests << [uri, request]
    Net::HTTPResponse::CODE_TO_OBJ.fetch(@code).new("1.1", @code, "").tap do |response|
      response.instance_variable_set(:@body, "")
      response.instance_variable_set(:@read, true)
    end
  end

  def install
    PushSubscription.transport = self
    yield self
  ensure
    PushSubscription.transport = nil
  end
end

# Requests made by integration tests share the test's thread, so Current (the
# per-request cache of settings, user and household) would leak from one
# request into the next and into the test's own assertions.
module ResetCurrentAfterRequest
  def process(...)
    super(...)
  ensure
    Current.reset
  end
end
ActionDispatch::Integration::Session.prepend(ResetCurrentAfterRequest)

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
