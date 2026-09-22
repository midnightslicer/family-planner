# Public invitation join flow. GET shows app name + inviter + household and a
# join form; POST creates the user + membership, marks the invitation
# accepted, signs in, and redirects to the dashboard.
class InvitationsController < ApplicationController
  before_action :set_invitation

  # GET /invitations/:token
  def show
    if @invitation.nil? || !@invitation.pending?
      render :invalid, status: :unprocessable_entity
    end
  end

  # POST /invitations/:token/join
  def join
    if @invitation.nil? || !@invitation.pending?
      render :invalid, status: :unprocessable_entity
      return
    end

    @user = User.new(join_params.except(:token))
    @user.email = @invitation.email
    if @user.save && create_membership
      sign_in @user
      redirect_to dashboard_path, notice: "Welcome to #{@invitation.household.name}!"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_invitation
    @invitation = Invitation.find_by_raw_token(params[:token])
  end

  def create_membership
    HouseholdMembership.create(user: @user, household: @invitation.household) &&
      @invitation.update(accepted_at: Time.current)
  end

  def join_params
    params.require(:user).permit(:display_name, :handle, :email, :password, :password_confirmation, :color, :token)
  end
end