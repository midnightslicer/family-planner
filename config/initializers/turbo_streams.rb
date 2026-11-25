# Live updates only reach people allowed to see them: see
# ApplicationCable::StreamAuthorization.
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.prepend(ApplicationCable::StreamAuthorization) unless Turbo::StreamsChannel < ApplicationCable::StreamAuthorization
end
