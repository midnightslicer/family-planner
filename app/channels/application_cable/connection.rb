module ApplicationCable
  # Websocket connection for Turbo Stream broadcasts. Everything in the app,
  # the wall included, needs a signed-in person, so anonymous connections are
  # refused. Streams are still authorised by their signed names.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user(:user) || reject_unauthorized_connection
    end
  end
end
