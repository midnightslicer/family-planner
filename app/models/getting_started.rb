# The "getting started" card on the dashboard: the few things that make the
# board useful, ticked off from real state, hidden once dismissed or done.
class GettingStarted
  Step = Struct.new(:key, :title, :detail, :done, :link_label, :path, keyword_init: true)

  def initialize(user, household)
    @user = user
    @household = household
  end

  def visible?
    @user.onboarding_dismissed_at.nil? && !steps.reject { |step| step.key == :wall }.all?(&:done)
  end

  def steps
    @steps ||= [
      invite_step,
      Step.new(key: :task, title: "Add something you're doing",
               detail: "Your card on the board shows your current task and what's next.",
               done: @household.tasks.exists?, link_label: "Add a task", path: routes.new_task_path),
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

  def invite_step
    return unless @user.admin?

    Step.new(key: :invite, title: "Invite your family",
             detail: "Each person gets a single-use link. Email it, or copy it into a text message.",
             done: @household.users.count > 1 || @household.invitations.exists?,
             link_label: "Invite someone", path: routes.new_admin_invitation_path)
  end

  def wall_step
    return unless @user.admin?

    Step.new(key: :wall, title: "Put the board on a spare tablet (optional)",
             detail: "The wall page needs no sign-in and updates live. Open it on the tablet and add it to the home screen.",
             done: false, link_label: "Get the wall link", path: routes.edit_admin_household_path(@household))
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
