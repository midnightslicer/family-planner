module Admin
  class InvitationsController < BaseController
    def index
      @invitations = Invitation.includes(:household, :invited_by).order(created_at: :desc)
    end

    def new
      @invitation = Invitation.new
      @households = Household.order(:name)
    end

    # Creates the invitation and sends InvitationMailer#invite with a join
    # link containing the raw token (shown only once). Falls back to showing
    # the raw link inline if mail delivery is not configured.
    def create
      @households = Household.order(:name)
      @invitation = Invitation.new(invitation_params.merge(invited_by: current_user))
      if @invitation.save
        join_url = invitation_url(@invitation.raw_token, protocol: "https", host: mail_host)
        InvitationMailer.invite(@invitation, @invitation.raw_token, join_url).deliver_later
        redirect_to admin_invitations_path, notice: "Invitation sent to #{@invitation.email}. Share this link if the email can't be delivered: #{join_url}"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def resend
      invitation = Invitation.find(params[:id])
      if invitation.pending?
        raw = invitation.rotate_token!
        join_url = invitation_url(raw, protocol: "https", host: request.host)
        InvitationMailer.invite(invitation, raw, join_url).deliver_later
        redirect_to admin_invitations_path, notice: "Invitation resent to #{invitation.email}."
      else
        redirect_to admin_invitations_path, alert: "That invitation can no longer be used."
      end
    end

    def invitation_params
      params.require(:invitation).permit(:email, :household_id, :note)
    end

    def mail_host
      request.host
    end
  end
end