require "spec"

# Your application config
# If you have a testing environment, replace this with a test config file
require "../src/config"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"

# Binds to the system websocket endpoint
def new_websocket(path)
  socket = HTTP::WebSocket.new("localhost", path, 6000)
  yield socket
  spawn { socket.run }
  Fiber.yield
  socket.close
end
