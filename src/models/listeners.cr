require "./server_manager"

class Listeners
  @@udp_tracking = Hash(Int32, Hash(String, Array(Session))).new do |hash, key|
    hash[key] = Hash(String, Array(Session)).new { |h, k| h[k] = [] of Session }
  end

  # port => Server
  @@udp_servers = {} of Int32 => UDPSocket

  def self.stats
    sessions = Set(Session).new
    engine_listeners = {} of Int32 => Int32
    @@udp_tracking.each do |port, client_ip_to_sessions|
      client_ip_to_sessions.values.each { |sess| sessions.concat(sess) }
      engine_listeners[port] = sessions.size
      sessions.clear
    end

    # Websocket sessions, connected clients
    engine_listeners
  end

  def self.logger
    ActionController::Base.settings.logger
  end

  def self.open_udp_server(port : Int32, session : Session)
    sessions = @@udp_tracking[port]

    if sessions.empty?
      logger.info "opening UDP server on #{port}", " server_protocol=udp server_port=#{port}"
      server = UDPSocket.new
      server.bind("0.0.0.0", port)
      @@udp_servers[port] = server
      spawn { read_data(sessions, server, port) }
    end

    session.tracking.each do |address|
      sessions[address] << session
    end
  end

  def self.send_client_data(server_port, remote_ip, remote_port, data : Bytes)
    if server = @@udp_servers[server_port]?
      begin
        remote = Socket::IPAddress.new(remote_ip, remote_port.to_i)
        server.send(data, remote)
      rescue error : Socket::ConnectError
        # https://crystal-lang.org/api/0.34.0/UDPSocket.html
        logger.info "remote may not be listening #{error.inspect_with_backtrace}", " server_protocol=udp server_port=#{server_port} remote_ip=#{remote_ip} remote_port=#{remote_port}"
      end
    end
  end

  def self.close_udp_server(port : Int32, session : Session)
    if ip_sessions = @@udp_tracking[port]?
      remote_ips = session.tracking

      # Remove sessions from interested arrays
      empty = [] of String
      remote_ips.each do |remote_ip|
        if sessions = ip_sessions[remote_ip]?
          sessions.delete(session)
          empty << remote_ip if sessions.empty?
        end
      end

      # For all the empty sessions we want to close client connections
      # and delete the session array
      empty.each { |remote_ip| ip_sessions.delete(remote_ip) }

      # Check if the ip_sessions hash is empty, we'll close the server
      if ip_sessions.empty?
        @@udp_tracking.delete(port)
        server = @@udp_servers.delete(port)

        logger.info "closing UDP server on #{port}", " server_protocol=udp server_port=#{port}"
        server.try &.close
      end
    end
  end

  # =====================
  # Connection management
  # =====================
  def self.read_data(sessions, server, port)
    raw_data = Bytes.new(2048)
    while !server.closed?
      bytes_read, client_addr = server.receive(raw_data)
      break if bytes_read == 0 # IO was closed

      remote_ip = client_addr.address
      interested = sessions[remote_ip]?
      if interested.nil? || interested.empty?
        logger.warn "ignoring UDP data from #{remote_ip} on #{port}", " server_protocol=udp server_port=#{port} remote_ip=#{remote_ip} accepted=false"
        next
      end

      client_port = client_addr.port.to_u64

      data = raw_data[0, bytes_read]
      message = Session::Protocol.new
      message.message = Session::Protocol::MessageType::RECEIVED
      message.ip_address = remote_ip
      message.id_or_port = client_port
      message.data = data
      message = message.to_slice

      interested.each(&.io_callback(message))
    end
  rescue IO::Error
  end
end
