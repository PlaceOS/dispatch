require "./spec_helper"

describe Dispatcher do
  with_server do
    it "should open a new server and receive events" do
      received_open = false
      received_msg = ""
      received_close = false

      new_websocket("/api/server/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1") do |socket|
        socket.on_binary do |data|
          io = IO::Memory.new(data)
          message = io.read_bytes(Session::Protocol)

          #puts "GOT #{message.message} = #{data}"

          case message.message
          when Session::Protocol::MessageType::OPENED
            received_open = true
          when Session::Protocol::MessageType::RECEIVED
            received_msg = String.new(message.data)
          when Session::Protocol::MessageType::CLOSED
            received_close = true
          end
        end

        TCPSocket.open("localhost", 6001) do |client|
          tcp_connection = client
          client.write("testing".to_slice)
          sleep 1
        end

        # Wait for the client to close
        sleep 1
      end

      received_open.should eq(true)
      received_msg.should eq("testing")
      received_close.should eq(true)
    end

    it "should open a new server and send / receive events" do
      received_open = false
      received_msg = ""
      received_close = false
      sent_msg = ""

      new_websocket("/api/server/tcp_dispatch?bearer_token=testing&port=6001&accept=127.0.0.1") do |socket|
        socket.on_binary do |data|
          io = IO::Memory.new(data)
          message = io.read_bytes(Session::Protocol)

          case message.message
          when Session::Protocol::MessageType::OPENED
            received_open = true
          when Session::Protocol::MessageType::RECEIVED
            received_msg = String.new(message.data)
            message.message = Session::Protocol::MessageType::WRITE
            message.data = "reply".to_slice
            msg = message.to_slice
            socket.stream(msg.size) { |io| io << msg }
          when Session::Protocol::MessageType::CLOSED
            received_close = true
          end
        end

        TCPSocket.open("localhost", 6001) do |client|
          tcp_connection = client
          client.write("testing".to_slice)
          raw_data = Bytes.new(1024)
          #bytes_read = client.read(raw_data)
          #sent_msg = String.new(raw_data[0, bytes_read])
        end

        # Wait for the client to close
        sleep 1
      end

      received_open.should eq(true)
      received_msg.should eq("testing")
      sent_msg.should eq("reply")
      received_close.should eq(true)
    end
  end
end
