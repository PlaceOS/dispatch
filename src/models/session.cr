require "./servers"
require "bindata"
require "socket"

class Session
  Log = ::App::Log.for("session")

  class Protocol < BinData
    endian big

    enum MessageType : UInt8
      OPENED
      CLOSED
      RECEIVED
      WRITE
      CLOSE
    end

    field message : MessageType = MessageType::RECEIVED
    field ip_address : String
    field id_or_port : UInt64
    field data_size : UInt32, value: ->{ data.size }
    field data : Bytes = Bytes.new(0), length: ->{ data_size }
  end

  # Binary protocol: signal, remote_ip, client_id, size, data
  def initialize(@tcp_transport : Bool, @server_port : Int32, @websocket : HTTP::WebSocket, @tracking : Array(String))
    @connections = Hash(String, Array(UInt64)).new do |h, k|
      h[k] = [] of UInt64
    end
  end

  def configure_websocket
    @websocket.on_ping { @websocket.pong }
    if @tcp_transport
      @websocket.on_binary { |bytes| parse_tcp(bytes) }
    else
      @websocket.on_binary { |bytes| parse_udp(bytes) }
    end
    self
  end

  def parse_tcp(message)
    message = IO::Memory.new(message, false)
    message = message.read_bytes(Protocol)
    case message.message
    when Protocol::MessageType::WRITE
      Servers.send_client_data(@server_port, message.ip_address, message.id_or_port, message.data)
    when Protocol::MessageType::CLOSE
      Servers.close_client_connection(@server_port, message.ip_address, message.id_or_port)
    else
      Log.warn { "unexpected message type received #{message.message}" }
    end
  end

  def parse_udp(message)
    message = IO::Memory.new(message, false)
    message = message.read_bytes(Protocol)
    case message.message
    when Protocol::MessageType::WRITE
      Listeners.send_client_data(@server_port, message.ip_address, message.id_or_port, message.data)
    else
      Log.warn { "unexpected message type received #{message.message}" }
    end
  end

  # Array of IP addresses
  getter tracking : Array(String)

  # remote_ip => [client_ids]
  getter connections : Hash(String, Array(UInt64))

  # state callbacks:
  def connection_opened(remote_ip, client_id, message)
    @connections[remote_ip] << client_id
    @websocket.stream(true, message.size, &.write(message))
  end

  def io_callback(message)
    @websocket.stream(true, message.size, &.write(message))
  end

  def connection_closed(remote_ip, client_id, message)
    if clients = @connections[remote_ip]?
      clients.delete(client_id)
    end
    @websocket.stream(true, message.size, &.write(message))
  end
end
