require "spec"

# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

# Your application config
# If you have a testing environment, replace this with a test config file
require "../src/config"

# servers are closed asynchronously once the websocket closes
def wait_for_servers_to_close(client)
  100.times do
    stats = JSON.parse(client.get("/api/dispatch/v1?bearer_token=testing").body)
    break if stats["tcp_listeners"].as_h.empty?
    sleep 10.milliseconds
  end
end
