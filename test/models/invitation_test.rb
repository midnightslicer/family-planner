require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @household = households(:smiths)
    @admin = users(:admin)
  end

  test "raw token is shown only at generation; only the digest persists" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    raw = invitation.raw_token

    assert_not_nil raw
    assert_not_equal raw, invitation.token
    assert_equal Digest::SHA256.hexdigest(raw), invitation.token

    # Reloading loses the raw token — it exists only in memory at creation.
    reloaded = Invitation.find(invitation.id)
    assert_nil reloaded.raw_token
  end

  test "find_by_raw_token matches by digest" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    assert_equal invitation, Invitation.find_by_raw_token(invitation.raw_token)
    assert_nil Invitation.find_by_raw_token("bogus-token")
  end

  test "pending, expired, and accepted states" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    assert invitation.pending?
    assert_equal "pending", invitation.status

    invitation.accept!
    assert_equal "accepted", invitation.status
    assert invitation.accepted_at.present?
    assert_not invitation.pending?

    expired_invitation = Invitation.create!(email: "late@example.com", household: @household, invited_by: @admin)
    expired_invitation.update_column(:expires_at, 1.day.ago)
    assert expired_invitation.expired?
    assert_equal "expired", expired_invitation.status
  end

  test "accepting twice or after expiry is refused" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    assert invitation.accept!
    assert_not invitation.accept!      # second use refused

    expired_invitation = Invitation.create!(email: "late@example.com", household: @household, invited_by: @admin)
    expired_invitation.update_column(:expires_at, 1.day.ago)
    assert_not expired_invitation.accept!
    assert_nil expired_invitation.accepted_at
  end

  test "rotate_token! invalidates the old raw token" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    old_raw = invitation.raw_token

    new_raw = invitation.rotate_token!
    assert_not_equal old_raw, new_raw
    assert_nil Invitation.find_by_raw_token(old_raw)
    assert_equal invitation, Invitation.find_by_raw_token(new_raw)
  end

  test "accepted? reflects accepted_at" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    assert_not invitation.accepted?

    invitation.accept!
    assert invitation.accepted?
  end

  test "expiry defaults to seven days out" do
    invitation = Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)
    assert_in_delta 7.days.from_now, invitation.expires_at, 1.second
  end
end