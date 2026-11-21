# A first copy of every existing work schedule, so history starts now
# rather than at each person's next save.
class BackfillWorkScheduleVersions < ActiveRecord::Migration[8.1]
  def up
    select_rows("SELECT DISTINCT user_id FROM work_shifts").each do |(user_id)|
      shifts = select_all("SELECT weekday, from_time, until_time, place FROM work_shifts WHERE user_id = #{user_id.to_i} ORDER BY weekday").to_a
      availability = select_value("SELECT work_availability FROM users WHERE id = #{user_id.to_i}")
      execute <<~SQL
        INSERT INTO work_schedule_versions (user_id, effective_at, availability, shifts, created_at, updated_at)
        VALUES (#{user_id.to_i}, CURRENT_TIMESTAMP, #{connection.quote(availability)}, #{connection.quote(shifts.to_json)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end

  def down
  end
end
