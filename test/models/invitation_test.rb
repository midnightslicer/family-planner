require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @household = households(:smiths)
    @admin = users(:admin)
  end

  def invite(email = "new@example.com") = Invitation.create!(email: email, household: @household, invited_by: @admin)

  test "only the token's digest is stored; the raw token finds it until rotated" do
    invitation = invite
    raw = invitation.raw_token
    assert_equal Digest::SHA256.hexdigest(raw), invitation.token
    assert_nil Invitation.find(invitation.id).raw_token, "the raw token exists only at creation"
    assert_equal invitation, Invitation.find_by_raw_token(raw)
    assert_nil Invitation.find_by_raw_token("bogus-token")

    new_raw = invitation.rotate_token!
    assert_nil Invitation.find_by_raw_token(raw)
    assert_equal invitation, Invitation.find_by_raw_token(new_raw)
  end

  test "an invitation lasts seven days and can be accepted once" do
    invitation = invite
    assert_in_delta 7.days.from_now, invitation.expires_at, 1.second
    assert_equal "pending", invitation.status
    assert_not invitation.accepted?

    assert invitation.accept!
    assert invitation.accepted?
    assert_equal "accepted", invitation.status
    assert_not invitation.accept!, "second use refused"
  end

  test "an expired invitation can't be accepted" do
    invitation = invite("late@example.com")
    invitation.update_column(:expires_at, 1.day.ago)
    assert invitation.expired?
    assert_equal "expired", invitation.status
    assert_not invitation.accept!
    assert_nil invitation.accepted_at
  end
end
