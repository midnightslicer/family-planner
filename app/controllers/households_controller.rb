class HouseholdsController < ApplicationController
  include ActionController::Live

  # POST /switch_household — validates membership, updates the session.
  def switch
    household = current_user.households.find_by(id: params[:household_id])
    if household
      session[:current_household_id] = household.id
      redirect_back(fallback_location: dashboard_path, notice: "Switched to #{household.name}.")
    else
      redirect_back(fallback_location: dashboard_path, alert: "You are not a member of that household.")
    end
  end

  # GET /households/:id/stream — SSE endpoint. Accessible to household
  # members, or anonymously with the household's unguessable dashboard
  # token (used by the public kiosk wall).
  def stream
    household = find_stream_household
    return head :not_found unless household

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    queue = TaskBroadcaster.subscribe(household.id)
    response.stream.write ": connected\n\n"
    loop do
      message = queue.pop
      response.stream.write "event: task_update\ndata: #{message}\n\n"
    rescue ActionController::Live::ClientDisconnected
      break
    end
  ensure
    TaskBroadcaster.unsubscribe(household&.id, queue) if queue
    response.stream.close
  end

  # GET /households/:id/cards/:user_id — person card fragment for live swaps.
  # Same access rules as the stream.
  def card
    household = find_stream_household
    user = household&.users&.order(:display_name)&.find_by(id: params[:user_id])
    return head :not_found unless household && user

    render partial: "shared/person_card", locals: { user: user, household: household }, layout: false
  end

  private

  # Members access their household's stream; the wall supplies the household's
  # dashboard token as a query parameter.
  def find_stream_household
    if current_user
      current_user.households.find_by(id: params[:id])
    elsif params[:token].present?
      Household.find_by(id: params[:id], dashboard_token: params[:token])
    end
  end
end