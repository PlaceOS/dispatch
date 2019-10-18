require "uuid"

abstract class Application < ActionController::Base
  before_action :set_request_id

  # This makes it simple to match client requests with server side logs.
  def set_request_id
    logger.client_ip = client_ip
    response.headers["X-Request-ID"] = logger.request_id = UUID.random.to_s
    # Which module requested this server
    logger.event_source = request.headers["X-Module-ID"]?
  end
end
