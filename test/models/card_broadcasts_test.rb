require "test_helper"
require "turbo/broadcastable/test_helper"

# Person cards re-render live (Household#broadcast_member_cards). Inside
# Household.batching_cards, as every request is, each card goes out once at
# the end however many records changed.
class CardBroadcastsTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @smiths = households(:smiths)
    @admin = users(:admin)
    @member = users(:member)
  end

  def card_replaces(user)
    capture_turbo_stream_broadcasts([ @smiths, :members ])
      .count { |stream| stream["action"] == "replace" && stream["target"] == "person_card_user_#{user.id}" }
  end

  test "without a batch, every change re-renders the card" do
    Task.create!(household: @smiths, title: "One", assigned_to: @member)
    Task.create!(household: @smiths, title: "Two", assigned_to: @member)
    assert_operator card_replaces(@member), :>=, 2
  end

  test "in a batch, each person's card goes out once, at the end" do
    Household.batching_cards do
      Task.create!(household: @smiths, title: "One", assigned_to: @member)
      task = Task.create!(household: @smiths, title: "Two", assigned_to: @member, created_by: @admin)
      task.assignments.create!(user: @admin, status: "accepted")
      assert_equal 0, card_replaces(@member), "nothing goes out mid-batch"
    end
    assert_equal 1, card_replaces(@member)
    assert_equal 1, card_replaces(@admin)
  end

  test "a nested batch leaves the sending to the outer one" do
    Household.batching_cards do
      Household.batching_cards { Task.create!(household: @smiths, title: "Inner", assigned_to: @member) }
      assert_equal 0, card_replaces(@member)
      Task.create!(household: @smiths, title: "Outer", assigned_to: @member)
    end
    assert_equal 1, card_replaces(@member)
  end

  test "a batch that raises still sends what was saved, and closes" do
    assert_raises(RuntimeError) do
      Household.batching_cards do
        Task.create!(household: @smiths, title: "Saved", assigned_to: @member)
        raise "boom"
      end
    end
    assert_equal 1, card_replaces(@member)
    assert_nil Current.pending_cards
  end
end

class CardBroadcastsPerRequestTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  test "adding something for two people re-renders each of their cards once" do
    smiths = households(:smiths)
    admin, member = users(:admin), users(:member)
    sign_in admin
    post tasks_path, params: { task: { title: "Picnic", assignee_ids: [ admin.id, member.id ] } }
    assert_redirected_to tasks_path

    replaces = capture_turbo_stream_broadcasts([ smiths, :members ]).select { |stream| stream["action"] == "replace" }
    assert_equal [ "person_card_user_#{admin.id}", "person_card_user_#{member.id}" ].sort, replaces.map { |stream| stream["target"] }.sort
  end
end
