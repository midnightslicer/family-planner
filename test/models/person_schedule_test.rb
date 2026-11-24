require "test_helper"

class PersonScheduleTest < ActiveSupport::TestCase
  setup do
    @smiths = households(:smiths)
    @admin = users(:admin)
    @member = users(:member)
  end

  test "the family view's batched schedules match each person's own" do
    travel_to Time.zone.local(2026, 11, 24, 10, 0) do
      @member.work_shifts.create!(weekday: Date.current.wday, from_time: "13:00", until_time: "17:00")
      Task.create!(household: @smiths, title: "Shared", assigned_to: @member, starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
        .assignments.create!(user: @admin, status: "accepted")
      Task.create!(household: @smiths, title: "Mine", assigned_to: @admin)
      Task.create!(household: @smiths, title: "Secret", assigned_to: @member, private: true, created_by: @member)
      Task.create!(household: @smiths, title: "Later", assigned_to: @member, due_on: Date.current + 2)
      Task.create!(household: @smiths, title: "Next week", assigned_to: @admin, starts_at: 20.days.from_now)
      done = Task.create!(household: @smiths, title: "Done", assigned_to: @member)
      done.update!(status: :completed, finished_at: Time.current)

      members = @smiths.board_members
      family = PersonSchedule.for_family(@smiths, members, viewer: @admin)
      members.each do |member|
        own = PersonSchedule.new(@smiths, member, viewer: @admin)
        batched = family.fetch(member)
        %i[today todos later done].each do |list|
          assert_equal own.public_send(list).map(&:title), batched.public_send(list).map(&:title), "#{member.handle} #{list}"
        end
        assert_equal [own.now&.title, own.work&.starts_at], [batched.now&.title, batched.work&.starts_at]
      end
      assert_equal ["Shared"], family.fetch(@admin).today.map(&:title)
      assert_equal ["Shared", "Work"], family.fetch(@member).today.map(&:title)
      assert_not_includes family.fetch(@member).todos.map(&:title), "Secret", "others' private to-dos stay hidden"
    end
  end
end
