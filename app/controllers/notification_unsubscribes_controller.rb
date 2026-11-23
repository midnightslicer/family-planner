# "Unsubscribe from these emails" (NotificationMailer). No sign-in: the
# signed token says who and which kind of update.
#
# GET only shows a confirm button, because mail scanners follow links.
# POST turns that category's email off; it's also the RFC 8058 one-click
# target mail apps post to from their own Unsubscribe button, without a
# CSRF token, so forgery protection is off for it. The token is the
# authorisation, and the only thing it can do is stop an email.
class NotificationUnsubscribesController < ApplicationController
  skip_forgery_protection only: :create
  rate_limit to: 30, within: 1.minute, with: -> { head :too_many_requests }

  before_action :resolve_token

  def show
  end

  def create
    NotificationUnsubscribe.unsubscribe!(@person, @category.key)
    render :done
  end

  private

  def resolve_token
    @person, key = NotificationUnsubscribe.resolve(params[:token])
    return render(:invalid, status: :not_found) unless @person

    @category = NotificationPreference.category(key)
  end
end
