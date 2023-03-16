require "../models/session"
require "placeos-models/version"
require "../constants"

class Dispatcher < Application
  base "/api/dispatch/v1"

  # =====================
  # Filters
  # =====================

  before_action :authenticate, except: [:healthcheck, :version]

  @[AC::Route::Filter(:before_action, except: [:healthcheck, :version])]
  def authenticate
    raise Error::Unauthorized.new("invalid authorisation token") unless acquire_token == App::AUTH_SECRET
  end

  def acquire_token : String?
    if token = request.headers["Authorization"]?
      token.lchop("Bearer ").rstrip
    elsif token = params["bearer_token"]?
      token.strip
    end
  end

  # =====================
  # Routes
  # =====================

  struct Stats
    include JSON::Serializable

    getter udp_listeners : Hash(Int32, Int32)
    getter tcp_listeners : Hash(Int32, Int32)
    getter tcp_clients : Hash(Int32, Int32)

    def initialize(@udp_listeners, @tcp_listeners, @tcp_clients)
    end
  end

  # Returns details about open servers and number of engine drivers listening.
  # Also returns details about the number of TCP client connections to the servers
  @[AC::Route::GET("/")]
  def index : Stats
    udp_listeners = Listeners.stats
    tcp_listeners, tcp_clients = Servers.stats

    Stats.new(
      udp_listeners: udp_listeners,
      tcp_listeners: tcp_listeners,
      tcp_clients: tcp_clients,
    )
  end

  # used to check service is responding
  @[AC::Route::GET("/healthz")]
  def healthcheck : Nil
  end

  # returns the service commit level and build time
  @[AC::Route::GET("/version")]
  def version : PlaceOS::Model::Version
    PlaceOS::Model::Version.new(
      version: App::VERSION,
      build_time: App::BUILD_TIME,
      commit: App::BUILD_COMMIT,
      service: App::APP_NAME
    )
  end

  # Registers interest in TCP connections being opened on a certain port
  @[AC::Route::WebSocket("/tcp_dispatch")]
  def tcp_dispatch(ws,
                   @[AC::Param::Info(description: "the port we expect the client to connect to", example: "5001")]
                   port : UInt32,
                   @[AC::Param::Info(description: "a list of ip addresses we expect to connect", example: "192.168.0.2,10.0.0.50")]
                   accept : String) : Nil
    port = port.to_i
    ip_addresses = accept.split(",")

    Log.info { {server_protocol: "tcp", server_port: port, accepting: ip_addresses, message: "new TCP server requested"} }

    session = Session.new(true, port, ws, ip_addresses)
    Servers.open_tcp_server(port, session.configure_websocket)
    ws.on_close { Servers.close_tcp_server(port, session) }
  end

  # registers interest of incoming UDP data
  @[AC::Route::WebSocket("/udp_dispatch")]
  def udp_dispatch(ws,
                   @[AC::Param::Info(description: "the port we expect the client to connect to", example: "5001")]
                   port : UInt32,
                   @[AC::Param::Info(description: "a list of ip addresses we expect to connect", example: "192.168.0.2,10.0.0.50")]
                   accept : String) : Nil
    port = port.to_i
    ip_addresses = accept.split(",")

    Log.info { {server_protocol: "udp", server_port: port, accepting: ip_addresses, message: "new UDP server requested"} }

    session = Session.new(false, port, ws, ip_addresses)
    Listeners.open_udp_server(port, session.configure_websocket)
    ws.on_close { Listeners.close_udp_server(port, session) }
  end
end
