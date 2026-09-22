# Devise registrations overridden: joining is invite-only. The signup form is
# replaced by a "join requires an invite" screen; the only join path is the
# invitation link (GET /invitations/:token).
class RegistrationsController < Devise::RegistrationsController
  # GET /users/sign_up — shows the invite-only screen, or forwards straight
  # to the join form when a valid pending token is supplied.
  def new
    if params[:invitation_token].present?
      invitation = Invitation.find_by_raw_token(params[:invitation_token])
      return redirect_to invitation_path(params[:invitation_token]) if invitation&.pending?
    end
    render :new
  end

  # POST /users — self-serve signup is never allowed; the first account comes
  # from the setup wizard, everyone else from invitations.
  def create
    redirect_to new_user_registration_path, alert: "Joining requires an invite. Ask the household admin for an invitation link."
  end
end