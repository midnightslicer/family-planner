module ApplicationCable
  # Websocket connection for Turbo Stream broadcasts. Streams are authorised
  # by their signed names (a dashboard only renders the names its viewer may
  # see, and the wall's come from its secret token), so anonymous wall
  # screens can connect too. Signed-in people are identified for the logs.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user(:user)
    end
  end
end
