module ApplicationCable
  # Turbo's signed stream names never expire and aren't tied to a person, so
  # someone removed from a household could keep a page's signed name and go
  # on hearing its live updates. Prepended to Turbo::StreamsChannel (see
  # config/initializers/turbo_streams.rb), so a subscription is also checked
  # against who is connected: a household of theirs, or their own toasts.
  module StreamAuthorization
    def subscribed
      name = verified_stream_name_from_params
      if name && allowed_stream_names.include?(name)
        stream_from name
      else
        reject
      end
    end

    private

    def allowed_stream_names
      [ [ current_user, :notifications ], *current_user.households.map { |household| [ household, :members ] } ]
        .map { |streamables| self.class.send(:stream_name_from, streamables) }
    end
  end
end
