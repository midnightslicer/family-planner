require "test_helper"

class NotificationUnsubscribeTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @member.notification_preferences.create!(category: "pets", push: true, email: true)
    @member.notification_preferences.create!(category: "assigned", push: true, email: true)
    @token = NotificationUnsubscribe.token_for(@member, "pets")
  end

  test "GET only asks; it changes nothing (mail scanners follow links)" do
    get notification_unsubscribe_path(@token)
    assert_response :success
    assert_select "h1", "Stop these emails?"
    assert_select "form[action=?][method=post]", notification_unsubscribe_path(@token)
    assert @member.notification_preference("pets").email
  end

  test "POST turns off only that category's email, signed out" do
    post notification_unsubscribe_path(@token)
    assert_response :success
    assert_select "h1", "Unsubscribed"
    @member.notification_preferences.reset
    assert_not @member.notification_preference("pets").email
    assert @member.notification_preference("pets").push
    assert @member.notification_preference("assigned").email
  end

  test "mail apps' one-click POST works without a CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    post notification_unsubscribe_path(@token), params: "List-Unsubscribe=One-Click",
                                                headers: { "Content-Type" => "application/x-www-form-urlencoded" }
    assert_response :success
    @member.notification_preferences.reset
    assert_not @member.notification_preference("pets").email
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a default category gets a row that keeps its push default" do
    token = NotificationUnsubscribe.token_for(@member, "replies")
    post notification_unsubscribe_path(token)
    replies = @member.notification_preferences.find_by!(category: "replies")
    assert replies.push
    assert_not replies.email
  end

  test "a tampered or foreign token does nothing" do
    other = NotificationUnsubscribe.token_for(users(:admin), "pets")
    tampered = other.sub(/.\z/) { |c| c == "A" ? "B" : "A" }
    [tampered, "nonsense", Rails.application.message_verifier(:x).generate([@member.id, "pets"])].each do |token|
      post "/notifications/unsubscribe/#{CGI.escape(token)}"
      assert_response :not_found, token
    end
    @member.notification_preferences.reset
    assert @member.notification_preference("pets").email
  end
end
