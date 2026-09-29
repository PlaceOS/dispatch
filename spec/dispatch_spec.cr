require "./spec_helper"
require "placeos-models/version"

describe Dispatcher do
  client = AC::SpecHelper.client

  it "should healthcheck" do
    result = client.get "/api/dispatch/v1/healthz"
    result.status_code.should eq 200
  end

  it "should check version" do
    result = client.get "/api/dispatch/v1/version"
    result.status_code.should eq 200
    PlaceOS::Model::Version.from_json(result.body).service.should eq "dispatch"
  end

  it "should open a new server and receive events" do
    received_open = false
    received_msg = ""
    received_close = false

    socket = client.establish_ws("/api/dispatch/v1/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1")
    socket.on_binary do |data|
      io = IO::Memory.new(data)
      message = io.read_bytes(Session::Protocol)

      # puts "GOT #{message.message} = #{data}"

      case message.message
      when Session::Protocol::MessageType::OPENED
        received_open = true
      when Session::Protocol::MessageType::RECEIVED
        received_msg = String.new(message.data)
      when Session::Protocol::MessageType::CLOSED
        received_close = true
        socket.close
      else
      end
    end

    # Connect the expected client
    spawn do
      TCPSocket.open("localhost", 6001) do |_client|
        _client.write("testing".to_slice)
      end
    end

    # Wait for the client to close
    socket.run
    wait_for_servers_to_close(client)

    received_open.should eq(true)
    received_msg.should eq("testing")
    received_close.should eq(true)
  end

  it "should open a new server and send / receive events" do
    received_open = false
    received_msg = ""
    received_close = false
    sent_msg = ""
    middle_stats = nil

    socket = client.establish_ws("/api/dispatch/v1/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1")
    socket.on_binary do |data|
      io = IO::Memory.new(data)
      message = io.read_bytes(Session::Protocol)

      case message.message
      when Session::Protocol::MessageType::OPENED
        received_open = true
      when Session::Protocol::MessageType::RECEIVED
        received_msg = String.new(message.data)

        # Grab the stats here
        result = client.get "/api/dispatch/v1?bearer_token=testing"
        middle_stats = JSON.parse(result.body)

        # Send a reply back
        message.message = Session::Protocol::MessageType::WRITE
        message.data = "reply".to_slice
        msg = message.to_slice

        socket.stream(true, msg.size, &.write(msg))
      when Session::Protocol::MessageType::CLOSED
        received_close = true
        socket.close
      else
      end
    end

    spawn do
      TCPSocket.open("localhost", 6001) do |_client|
        # Send some data to the server
        _client.write("testing".to_slice)
        raw_data = Bytes.new(1024)

        # Get a response from the server
        bytes_read = _client.read(raw_data)
        sent_msg = String.new(raw_data[0, bytes_read])
      end
    end

    socket.run

    wait_for_servers_to_close(client)

    result = client.get "/api/dispatch/v1?bearer_token=testing"
    after_stats = JSON.parse(result.body)
    running_stats = middle_stats.not_nil!

    received_open.should eq(true)
    received_msg.should eq("testing")
    sent_msg.should eq("reply")
    received_close.should eq(true)

    # Ensure the stats are also correct
    running_stats["tcp_clients"].size.should eq(1)
    running_stats["tcp_listeners"].size.should eq(1)
    after_stats["tcp_clients"].size.should eq(0)
    after_stats["tcp_listeners"].size.should eq(0)
  end

  describe "TLS" do
    # connects a TLS client, sends "testing" and returns the reply
    tls_round_trip = ->(query : String) do
      received = [] of String
      sent_msg = ""

      socket = client.establish_ws("/api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6002&accept=127.0.0.1#{query}")
      socket.on_binary do |data|
        message = IO::Memory.new(data).read_bytes(Session::Protocol)
        received << message.message.to_s

        case message.message
        when Session::Protocol::MessageType::RECEIVED
          received << String.new(message.data)
          message.message = Session::Protocol::MessageType::WRITE
          message.data = "reply".to_slice
          msg = message.to_slice
          socket.stream(true, msg.size, &.write(msg))
        when Session::Protocol::MessageType::CLOSED
          socket.close
        else
        end
      end

      spawn do
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        TCPSocket.open("localhost", 6002) do |tcp|
          OpenSSL::SSL::Socket::Client.open(tcp, context, sync_close: true) do |tls|
            tls.sync = true
            tls.write("testing".to_slice)
            raw_data = Bytes.new(1024)
            bytes_read = tls.read(raw_data)
            sent_msg = String.new(raw_data[0, bytes_read])
          end
        end
      end

      socket.run
      wait_for_servers_to_close(client)
      received.should eq(["OPENED", "RECEIVED", "testing", "CLOSED"])
      sent_msg
    end

    it "should use a self-signed certificate when no key is provided" do
      tls_round_trip.call("").should eq("reply")
    end

    it "should generate a self-signed certificate for a provided private key" do
      key = OpenSSL::PKey::RSA.new(2048).to_pem
      tls_round_trip.call("&private_key=#{URI.encode_www_form(key)}").should eq("reply")
    end

    it "should use a provided certificate and private key" do
      key = OpenSSL::PKey::EC.new(256)
      cert = TLS.self_signed(key)
      tls_round_trip.call("&private_key=#{URI.encode_www_form(key.to_pem)}&certificate=#{URI.encode_www_form(cert)}").should eq("reply")
    end

    it "should reject invalid TLS configuration" do
      result = client.get("/api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6002&accept=127.0.0.1&private_key=invalid")
      result.status_code.should eq 400

      cert = TLS.self_signed(OpenSSL::PKey::RSA.new(2048))
      result = client.get("/api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6002&accept=127.0.0.1&certificate=#{URI.encode_www_form(cert)}")
      result.status_code.should eq 400

      other_key = URI.encode_www_form(OpenSSL::PKey::RSA.new(2048).to_pem)
      result = client.get("/api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6002&accept=127.0.0.1&certificate=#{URI.encode_www_form(cert)}&private_key=#{other_key}")
      result.status_code.should eq 400
    end

    it "should not open a TLS server on a port with a running TCP server" do
      tcp_socket = client.establish_ws("/api/dispatch/v1/tcp_dispatch?bearer_token=testing&port=6003&accept=127.0.0.1")
      spawn { tcp_socket.run }

      tls_socket = client.establish_ws("/api/dispatch/v1/tls_dispatch?bearer_token=testing&port=6003&accept=127.0.0.1")
      closed = false
      tls_socket.on_close { closed = true }
      tls_socket.run
      closed.should be_true

      tcp_socket.close
      wait_for_servers_to_close(client)
    end
  end
end
