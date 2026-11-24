# The "getting started" list: the few things that make the board useful,
# ticked off from real state. On the dashboard until dismissed or done; at
# the bottom of the account page until done.
class GettingStarted
  Step = Struct.new(:key, :title, :detail, :done, :link_label, :path, :skippable, :skipped, keyword_init: true)

  # `members`: the household's members, if the page has them loaded.
  def initialize(user, household, members: nil)
    @user = user
    @household = household
    @members = members
  end

  # On the dashboard until hidden or done.
  def visible?
    @user.onboarding_dismissed_at.nil? && !complete?
  end

  # Everything but the optional wall step is done. The account page shows
  # the list (done steps included) until then, even after it's hidden on
  # the dashboard.
  def complete?
    steps.reject { |step| step.key == :wall }.all?(&:done)
  end

  def steps
    @steps ||= [
      invite_step,
      time_zone_step,
      Step.new(key: :photo, title: "Add a profile picture",
               detail: "So everyone can spot you at a glance on the board and the wall.",
               done: @user.avatar_saved?, link_label: "Add one", path: routes.account_root_path),
      Step.new(key: :home, title: "Say which house you live in",
               detail: "The board groups everyone by the house they live in.",
               done: @user.home_in(@household).present?, link_label: "Set it", path: routes.account_root_path),
      work_step,
      Step.new(key: :task, title: "Put something on your schedule",
               detail: "A to-do, or something at a time like a call or a trip to town. Your card shows it while it's on.",
               done: @household.tasks.exists?, link_label: "Your day", path: routes.tasks_path),
      Step.new(key: :security, title: "Make signing in quicker and safer",
               detail: "Add a passkey (Face ID, fingerprint or device PIN) or turn on two-step verification.",
               done: @user.passkeys.exists? || @user.two_factor_enabled?, link_label: "Account", path: routes.account_root_path),
      wall_step
    ].compact
  end

  def done_count
    steps.count(&:done)
  end

  private

  def work_step
    skipped = @user.work_schedule_skipped_at.present?
    works = @user.works?
    Step.new(key: :work, title: "Add your work schedule",
             detail: skipped && !works ? "Skipped. You can add one any time from your day." :
                     "Your work hours show on your card, with how reachable you are. No set schedule? Skip it.",
             done: works || skipped, skipped: skipped && !works, skippable: true,
             link_label: "Add hours", path: routes.edit_work_schedule_path)
  end

  def invite_step
    return unless @user.admin?

    Step.new(key: :invite, title: "Invite your family",
             detail: "Each person gets a single-use link. Email it, or copy it into a text message.",
             done: (@members ? @members.size : @household.users.count) > 1 || @household.invitations.exists?,
             link_label: "Invite someone", path: routes.new_admin_invitation_path)
  end

  def time_zone_step
    return unless @user.admin?

    Step.new(key: :time_zone, title: "Set your household's time zone",
             detail: "So work hours, \"today\" and every time shown match home for everyone, wherever their phone is.",
             done: @household.time_zone.present?, link_label: "Set it", path: routes.edit_admin_household_path(@household))
  end

  def wall_step
    return unless @user.admin?

    Step.new(key: :wall, title: "Put the board on a spare tablet (optional)",
             detail: "The wall page updates live. Open it on the tablet, sign in once and add it to the home screen.",
             done: false, link_label: "Get the wall link", path: routes.edit_admin_household_path(@household))
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
