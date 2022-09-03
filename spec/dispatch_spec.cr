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
      TCPSocket.open("localhost", 6001) do |client|
        client.write("testing".to_slice)
      end
    end

    # Wait for the client to close
    socket.run

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
      TCPSocket.open("localhost", 6001) do |client|
        # Send some data to the server
        client.write("testing".to_slice)
        raw_data = Bytes.new(1024)

        # Get a response from the server
        bytes_read = client.read(raw_data)
        sent_msg = String.new(raw_data[0, bytes_read])
      end
    end

    socket.run

    sleep 0.5

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
end
