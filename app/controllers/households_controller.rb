class HouseholdsController < ApplicationController
  include ActionController::Live

  HEARTBEAT_SECONDS = 15
  POLL_SECONDS = 1

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
    last_write = Time.current
    loop do
      message = queue.pop(timeout: POLL_SECONDS)
      if message
        response.stream.write "event: task_update\ndata: #{message}\n\n"
        last_write = Time.current
      elsif Time.current - last_write >= HEARTBEAT_SECONDS
        # The heartbeat is also how a closed tab gets noticed: the write
        # raises ClientDisconnected and the thread exits.
        response.stream.write ": ping\n\n"
        last_write = Time.current
      end
      # An open stream holds the request's share of the load interlock, so a
      # pending dev code reload would block every other request behind it.
      # Hang up instead; EventSource reconnects on its own.
      break if reload_pending?
    rescue ActionController::Live::ClientDisconnected, IOError
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
  def reload_pending?
    Rails.application.config.enable_reloading && Rails.application.reloader.check!
  end

  def find_stream_household
    if current_user
      current_user.households.find_by(id: params[:id])
    elsif params[:token].present?
      Household.find_by(id: params[:id], dashboard_token: params[:token])
    end
  end
end