require "uuid"

abstract class Application < ActionController::Base
  Log = ::App::Log.for("controller")
  before_action :set_request_id

  # This makes it simple to match client requests with server side logs.
  def set_request_id
    request_id = UUID.random.to_s
    Log.context.set(
      client_ip: client_ip,
      request_id: request_id,
      event_source: request.headers["X-Module-ID"]? || "unknown",
    )
    response.headers["X-Request-ID"] = request_id
  end
end
