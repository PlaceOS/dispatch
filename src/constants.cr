require "action-controller/logger"
require "secrets-env"

module App
  APP_NAME     = "dispatch"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}
  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  Log         = ::Log.for(APP_NAME)
  LOG_BACKEND = ActionController.default_backend

  AUTH_SECRET = ENV["PLACE_SERVER_SECRET"]? || ENV["SERVER_SECRET"]? || "testing"

  ENVIRONMENT = ENV["SG_ENV"]? || "development"

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  def self.running_in_production?
    ENVIRONMENT == "production"
  end
end
