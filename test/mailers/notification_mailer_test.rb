require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  setup do
    @member = users(:member)
    @smiths = households(:smiths)
    Setting.set("app_url", "https://status.example.com")
  end

  def mail(**overrides)
    NotificationMailer.update(@member, category: "assigned", title: "Sam added you to Church", body: "Bring snacks.",
                                       path: "/tasks/5?household=#{@smiths.id}", household: @smiths, **overrides)
  end

  test "says what happened, links to it on the public address, and how to stop" do
    email = mail
    assert_equal [ @member.email ], email.to
    assert_equal "[The Smiths] Sam added you to Church", email.subject
    html = email.html_part.body.to_s
    text = email.text_part.body.to_s
    [ html, text ].each do |part|
      assert_includes part, "Bring snacks."
      assert_includes part, "https://status.example.com/tasks/5?household=#{@smiths.id}"
      assert_includes part, "https://status.example.com/account/notifications"
      assert_match %r{https://status\.example\.com/notifications/unsubscribe/[\w=-]+}, part
      assert_includes part, "Things for me"
    end
  end

  test "carries one-click unsubscribe headers" do
    email = mail
    assert_match %r{\A<https://status\.example\.com/notifications/unsubscribe/[\w=-]+>\z}, email["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", email["List-Unsubscribe-Post"].value
  end

  test "private items arrive redacted (the caller passes title_for)" do
    task = Task.create!(household: @smiths, title: "Surprise party", private: true, created_by: users(:admin))
    email = mail(title: "Admin User finished #{task.title_for(@member)}")
    assert_not_includes email.html_part.body.to_s, "Surprise party"
    assert_includes email.subject, "Busy"
  end

  test "user text is escaped in the HTML part" do
    assert_includes mail(title: "<script>x</script>").html_part.body.to_s, "&lt;script&gt;"
  end
end
