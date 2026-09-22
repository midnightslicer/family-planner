class InvitationMailer < ApplicationMailer
  def invite(invitation, raw_token, join_url)
    @invitation = invitation
    @raw_token = raw_token
    @join_url = join_url
    @household = invitation.household
    @inviter = invitation.invited_by
    @note = invitation.note
    @app_name = app_name

    mail(
      to: invitation.email,
      subject: "You're invited to join #{app_name} — #{@household.name}"
    )
  end
end