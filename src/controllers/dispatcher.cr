require "../models/session"

class Dispatcher < Application
  base "/api/server"
  before_action :authenticate

  ws "/tcp_dispatch" do |ws|
    port = params["port"].to_u32.to_i
    ip_addresses = params["accept"].split(",")

    logger.tag "new server requested", server_protocol: "tcp", server_port: port, accepting: ip_addresses

    session = Session.new(port, ws, ip_addresses, logger)
    session.configure_websocket
  end

  ws "/udp_dispatch" do |ws|
    port = params["port"].to_u32.to_i
    ip_addresses = Array(String).from_json(request.body.not_nil!)


  end

  AUTH_SECRET = ENV["SERVER_SECRET"]? || "testing"

  def authenticate
    head :unauthorized unless acquire_token == AUTH_SECRET
  end

  def acquire_token : String?
    if (token = request.headers["Authorization"]?)
      token.lchop("Bearer ").rstrip
    elsif (token = params["bearer_token"]?)
      token.strip
    end
  end
end
