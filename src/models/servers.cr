require "./server_manager"

class Servers
  Log = ::App::Log.for("servers")

  # port => {"remote ip" => [session_instance]}
  @@tcp_tracking = Hash(Int32, Hash(String, Array(Session))).new do |hash, key|
    hash[key] = Hash(String, Array(Session)).new { |h, k| h[k] = [] of Session }
  end

  # port => Server
  @@tcp_servers = {} of Int32 => TCPServerManager

  def self.stats
    sessions = Set(Session).new
    engine_listeners = {} of Int32 => Int32
    @@tcp_tracking.each do |port, client_ip_to_sessions|
      client_ip_to_sessions.values.each { |sess| sessions.concat(sess) }
      engine_listeners[port] = sessions.size
      sessions.clear
    end

    server_clients = {} of Int32 => Int32
    @@tcp_servers.each { |port, manager| server_clients[port] = manager.client_count }

    # Websocket sessions, connected clients
    {engine_listeners, server_clients}
  end

  def self.open_tcp_server(port : Int32, session : Session)
    sessions = @@tcp_tracking[port]

    if sessions.empty?
      Log.info { {server_protocol: "tcp", server_port: port.to_s, message: "opening TCP server on #{port}"} }
      server = TCPServer.new("0.0.0.0", port)
      manager = TCPServerManager.new(server)
      @@tcp_servers[port] = manager
      spawn { accept_clients(sessions, server, port, manager) }
    end

    session.tracking.each do |address|
      sessions[address] << session
    end
  end

  def self.close_client_connection(server_port, remote_ip, client_id)
    if manager = @@tcp_servers[server_port]?
      if connections = manager.connections[remote_ip]?
        if client = connections.delete(client_id)
          client.close unless client.closed?
        end
      end
    end
  end

  def self.send_client_data(server_port, remote_ip, client_id, data : Bytes)
    if manager = @@tcp_servers[server_port]?
      if connections = manager.connections[remote_ip]?
        if client = connections[client_id]?
          client.write(data) unless client.closed?
        end
      end
    end
  rescue IO::Error
  end

  def self.close_tcp_server(port : Int32, session : Session)
    if ip_sessions = @@tcp_tracking[port]?
      remote_ips = session.tracking
      tracking = [] of Tuple(String, UInt64)

      session.connections.each do |remote_ip, client_ids|
        client_ids.each do |client_id|
          tracking << {remote_ip, client_id}
        end
      end

      # Remove sessions from interested arrays
      empty = [] of String
      remote_ips.each do |remote_ip|
        if sessions = ip_sessions[remote_ip]?
          sessions.delete(session)
          empty << remote_ip if sessions.empty?
        end
      end

      manager = @@tcp_servers[port]

      # For all the empty sessions we want to close client connections
      # and delete the session array
      empty.each do |remote_ip|
        ip_sessions.delete(remote_ip)

        tracking.each do |tracking_remote, client_id|
          if remote_ip == tracking_remote
            manager.close_client(tracking_remote, client_id)
          end
        end
      end

      # Check if the ip_sessions hash is empty, we'll close the server
      if ip_sessions.empty?
        @@tcp_tracking.delete(port)
        @@tcp_servers.delete(port)

        Log.info { {message: "closing TCP server on #{port}", server_protocol: "tcp", server_port: port.to_s} }
        manager.close
      end
    end
  end

  # =====================
  # Connection management
  # =====================
  def self.accept_clients(sessions, server, port, manager)
    while client = server.accept?
      spawn { handle_client(sessions, client.not_nil!, port, manager) }
    end
  end

  def self.handle_client(sessions, client, port, manager)
    remote_ip = client.remote_address.address

    # Check if we are interested in this connection
    interested = sessions[remote_ip]?
    if interested.nil? || interested.empty?
      Log.warn { {message: "rejected connection TCP #{remote_ip} on #{port}", server_protocol: "tcp", server_port: port.to_s, remote_ip: remote_ip, accepted: "false"} }
      client.close
      return
    end
    Log.info { {message: "accepted connection TCP #{remote_ip} on #{port}", server_protocol: "tcp", server_port: port.to_s, remote_ip: remote_ip, accepted: "true"} }

    # Configure the connection
    client.tcp_keepalive_idle = 10
    client.tcp_nodelay = true
    client.sync = true

    # register the client so we can close the connection if the session drops
    client_id = manager.new_connection(remote_ip, client)

    # Inform sessions of the new connection
    message = Session::Protocol.new
    message.message = Session::Protocol::MessageType::OPENED
    message.ip_address = remote_ip
    message.id_or_port = client_id
    message = message.to_slice

    interested.each(&.connection_opened(remote_ip, client_id, message))

    begin
      raw_data = Bytes.new(2048)
      while !client.closed?
        bytes_read = client.read(raw_data)
        break if bytes_read == 0 # IO was closed

        data = raw_data[0, bytes_read].dup
        message = Session::Protocol.new
        message.message = Session::Protocol::MessageType::RECEIVED
        message.ip_address = remote_ip
        message.id_or_port = client_id
        message.data = data
        message = message.to_slice

        interested.each(&.io_callback(message))
      end
    rescue IO::Error
    ensure
      # remove the client and inform sessions
      manager.remove_connection(remote_ip, client_id)

      message = Session::Protocol.new
      message.message = Session::Protocol::MessageType::CLOSED
      message.ip_address = remote_ip
      message.id_or_port = client_id
      message = message.to_slice

      interested.each(&.connection_closed(remote_ip, client_id, message))
    end
  end
end
