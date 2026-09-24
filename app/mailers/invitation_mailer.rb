class InvitationMailer < ApplicationMailer
  def invite(invitation, join_url)
    @invitation = invitation
    @join_url = join_url
    @household = invitation.household
    @inviter = invitation.invited_by
    @note = invitation.note

    mail(to: invitation.email, subject: "Join #{@household.name} on #{@app_name}")
  end
end
