# Public invitation flow. The link's token is the only credential:
#   - new people create an account (passkey or password) and join;
#   - someone already signed in just confirms and joins the household;
#   - someone with an account who isn't signed in is sent to sign in first
#     and brought back here afterwards.
class InvitationsController < ApplicationController
  include AccountSignup

  before_action :set_invitation
  rate_limit to: 10, within: 1.minute, only: [:join, :passkey_options, :accept], with: -> {
    redirect_to invitation_path(params[:token]), alert: "Too many attempts. Wait a minute and try again."
  }

  # GET /invitations/:token
  def show
    if current_user
      render :accept
    elsif @invitation.existing_user
      store_location_for(:user, invitation_path(params[:token]))
      render :sign_in_first
    else
      @user = User.new(email: @invitation.email, color: User.suggested_color(@invitation.household))
    end
  end

  # POST /invitations/:token/passkey_options
  def passkey_options
    render_signup_passkey_options(build_user)
  end

  # POST /invitations/:token/join (new account)
  def join
    return redirect_to(invitation_path(params[:token])) if current_user

    @user = build_user
    if attach_signup_passkey(@user) && create_member
      sign_in(:user, @user)
      session[:current_household_id] = @invitation.household_id
      redirect_to dashboard_path, notice: "Welcome to #{@invitation.household.name}!"
    else
      render :show, status: :unprocessable_content
    end
  end

  # POST /invitations/:token/accept (already signed in)
  def accept
    return redirect_to(invitation_path(params[:token])) unless current_user

    unless @invitation.open_link? || @invitation.email == current_user.email
      return redirect_to(invitation_path(params[:token]),
                         alert: "This invitation was sent to #{@invitation.email}. Sign out and join with that address.")
    end

    Invitation.transaction do
      raise ActiveRecord::Rollback unless @invitation.accept!

      HouseholdMembership.find_or_create_by!(user: current_user, household: @invitation.household)
    end
    session[:current_household_id] = @invitation.household_id
    redirect_to dashboard_path, notice: "You've joined #{@invitation.household.name}."
  end

  private

  def set_invitation
    @invitation = Invitation.includes(:household, :invited_by).find_by_raw_token(params[:token])
    render :invalid, status: :not_found, formats: :html unless @invitation&.pending?
  end

  def build_user
    user = User.new(signup_params)
    user.email = @invitation.email if @invitation.email.present?
    user
  end

  def create_member
    created = false
    User.transaction do
      # Claim the invitation first: the conditional update makes it single use
      # even if the form is submitted twice at once.
      raise ActiveRecord::Rollback unless @invitation.accept!
      raise ActiveRecord::Rollback unless @user.save

      HouseholdMembership.create!(user: @user, household: @invitation.household)
      created = true
    end
    @user.errors.add(:base, "This invitation has already been used.") unless created || @user.errors.any?
    created
  end
end
