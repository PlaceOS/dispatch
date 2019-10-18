require "./servers"
require "bindata"
require "socket"

class Session
  class Protocol < BinData
    endian big

    enum MessageType
      OPENED
      CLOSED
      RECEIVED
      WRITE
      CLOSE
    end

    enum_field UInt8, message : MessageType = MessageType::RECEIVED
    string :ip_address
    uint64 :id_or_port
    uint32 :data_size, value: ->{ data.size }
    bytes :data, length: ->{ data_size }, default: Bytes.new(0)
  end

  # Binary protocol: signal, remote_ip, client_id, size, data
  def initialize(@server_port : Int32, @websocket : HTTP::WebSocket, @tracking : Array(String), @logger : Logger = Logger.new(STDOUT))
    @connections = Hash(String, Array(UInt64)).new do |h, k|
      h[k] = [] of UInt64
    end
  end

  def configure_websocket
    @websocket.on_ping { @websocket.pong }
    @websocket.on_close { Servers.close_tcp_server(@server_port, self) }
    @websocket.on_binary { |bytes| parse(bytes) }
    Servers.open_tcp_server(@server_port, self)
  end

  def parse(message)
    message = IO::Memory.new(message, false)
    message = message.read_bytes(Protocol)
    case message.message
    when Protocol::MessageType::WRITE
      Servers.send_client_data(@server_port, message.ip_address, message.id_or_port, message.data)
    when Protocol::MessageType::CLOSE
      Servers.close_client_connection(@server_port, message.ip_address, message.id_or_port)
    else
      @logger.warn "unexpected message type received #{message.message}"
    end
  end

  # Array of IP addresses
  getter tracking : Array(String)

  # remote_ip => [client_ids]
  getter connections : Hash(String, Array(UInt64))

  # state callbacks:
  def connection_opened(remote_ip, client_id, message)
    @connections[remote_ip] << client_id
    @websocket.stream { |io| io.write message }
  end

  def io_callback(message)
    @websocket.stream { |io| io.write message }
  end

  def connection_closed(remote_ip, client_id, message)
    if clients = @connections[remote_ip]?
      clients.delete(client_id)
    end
    @websocket.stream { |io| io.write message }
  end
end
