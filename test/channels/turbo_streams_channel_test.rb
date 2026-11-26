require "test_helper"

# Signed stream names never expire, so a subscription is also checked
# against who's connected (ApplicationCable::StreamAuthorization).
class TurboStreamsChannelTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  setup do
    @member = users(:member)
    @household = households(:smiths)
    stub_connection current_user: @member
  end

  test "members hear their household and their own notifications" do
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ @household, :members ])
    assert subscription.confirmed?
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ @member, :notifications ])
    assert subscription.confirmed?
  end

  test "a signed name is no use to someone who left, or for another person's toasts" do
    @member.household_memberships.destroy_all
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ @household, :members ])
    assert subscription.rejected?
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ users(:admin), :notifications ])
    assert subscription.rejected?
  end
end
