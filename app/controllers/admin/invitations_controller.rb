module Admin
  class InvitationsController < BaseController
    def index
      @invitations = Invitation.includes(:household, :invited_by).order(created_at: :desc)
    end

    def new
      @invitation = Invitation.new(household: current_household)
      @households = Household.order(:name)
    end

    # The join link holds the raw token, which is only known right now, so
    # it's handed to #show once through the flash for copying.
    def create
      @invitation = Invitation.new(invitation_params.merge(invited_by: current_user))
      if @invitation.save
        join_url = join_link(@invitation.raw_token)
        emailed = send_invite(@invitation, join_url)
        flash[:invite_link] = join_url
        flash[:notice] = emailed ? "Invitation emailed to #{@invitation.email}." : "Invitation created. Copy the link below and send it however you like."
        redirect_to admin_invitation_path(@invitation)
      else
        @households = Household.order(:name)
        render :new, status: :unprocessable_content
      end
    end

    def show
      @invitation = Invitation.includes(:household).find(params[:id])
      @join_url = flash[:invite_link]
    end

    def resend
      invitation = Invitation.find(params[:id])
      if invitation.pending?
        join_url = join_link(invitation.rotate_token!)
        emailed = send_invite(invitation, join_url)
        flash[:invite_link] = join_url
        flash[:notice] = emailed ? "New link emailed to #{invitation.email}; the old link no longer works." : "New link created; the old one no longer works."
        redirect_to admin_invitation_path(invitation)
      else
        redirect_to admin_invitations_path, alert: "That invitation can no longer be used."
      end
    end

    def destroy
      Invitation.find(params[:id]).destroy
      redirect_to admin_invitations_path, notice: "Invitation revoked.", status: :see_other
    end

    private

    def invitation_params
      params.require(:invitation).permit(:email, :household_id, :note)
    end

    # APP_URL (or the URL saved at setup) rather than the request's Host
    # header, which a client controls.
    def join_link(raw_token)
      invitation_url(raw_token, **AppSettings.url_options)
    end

    def send_invite(invitation, join_url)
      return false unless invitation.email.present? && AppSettings.smtp_configured?

      InvitationMailer.invite(invitation, join_url).deliver_later
      true
    end
  end
end
