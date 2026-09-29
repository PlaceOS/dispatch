class TCPServerManager
  def initialize(@server, @tls = nil)
    @connections = Hash(String, Hash(UInt64, IO)).new do |h, k|
      h[k] = {} of UInt64 => IO
    end
  end

  property server : TCPServer

  # clients are expected to negotiate TLS when this is set
  getter tls : OpenSSL::SSL::Context::Server?
  property client_id : UInt64 = 0
  property client_count : Int32 = 0

  # "remote ip" => { client_id => socket }
  property connections : Hash(String, Hash(UInt64, IO))

  def tls? : Bool
    !@tls.nil?
  end

  def new_connection(ip : String, client : IO) : UInt64
    id = @client_id
    @client_id += 1

    @client_count += 1
    @connections[ip][id] = client
    id
  end

  def remove_connection(ip : String, id : UInt64) : Int32
    if connections = @connections[ip]?
      if client = connections.delete(id)
        @client_count -= 1
        client.close unless client.closed?
      end
    end

    @client_count
  end

  def close
    @server.close
    @connections.each_value do |clients|
      clients.each_value(&.close)
    end
  end

  def close_client(remote_ip, client_id : UInt64)
    if clients = @connections[remote_ip]?
      if client = clients.delete(client_id)
        client.close unless client.closed?
      end
    end
  end
end
