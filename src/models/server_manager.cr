
class TCPServerManager
  def initialize(@server)
    @connections = Hash(String, Hash(UInt64, IPSocket)).new do |h, k|
      h[k] = {} of UInt64 => IPSocket
    end
  end

  property server : TCPServer
  property client_id : UInt64 = 0
  property client_count : Int32 = 0

  # "remote ip" => { client_id => socket }
  property connections : Hash(String, Hash(UInt64, IPSocket))

  def new_connection(ip : String, client : IPSocket) : UInt64
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
