# The wall needs a signed-in member now, so its URL no longer has to be an
# unguessable secret: a readable slug from the household's name instead
# (/h/the-smiths). Old /h/<random> links stop working.
class ReplaceDashboardTokenWithSlug < ActiveRecord::Migration[8.1]
  def up
    add_column :households, :slug, :string

    taken = []
    select_rows("SELECT id, name FROM households ORDER BY id").each do |id, name|
      base = name.to_s.parameterize.presence || "home"
      slug = base
      count = 1
      slug = "#{base}-#{count += 1}" while taken.include?(slug)
      taken << slug
      execute("UPDATE households SET slug = #{quote(slug)} WHERE id = #{id.to_i}")
    end

    change_column_null :households, :slug, false
    add_index :households, :slug, unique: true
    remove_index :households, :dashboard_token
    remove_column :households, :dashboard_token
  end

  def down
    add_column :households, :dashboard_token, :string
    select_values("SELECT id FROM households").each do |id|
      execute("UPDATE households SET dashboard_token = #{quote(SecureRandom.hex(16))} WHERE id = #{id.to_i}")
    end
    change_column_null :households, :dashboard_token, false
    add_index :households, :dashboard_token, unique: true
    remove_index :households, :slug
    remove_column :households, :slug
  end
end
