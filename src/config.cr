# Application dependencies
require "action-controller"
require "active-model"
PROD = ENV["SG_ENV"]? == "production"

# Allows request IDs to be configured for logging
# You can extend this with additional properties
ActionController::Logger.add_tag client_ip
ActionController::Logger.add_tag request_id
ActionController::Logger.add_tag event_source

filter_params = ["bearer_token", "password"]
logger = ActionController::Base.settings.logger
logger.level = PROD ? Logger::INFO : Logger::DEBUG

# Application code
require "./controllers/application"
require "./controllers/*"
require "./models/*"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(!PROD),
  ActionController::LogHandler.new(filter_params),
  HTTP::CompressHandler.new
)

# Configure session cookies
# NOTE:: Change these from defaults
ActionController::Session.configure do |settings|
  settings.key = ENV["COOKIE_SESSION_KEY"]? || "_spider_gazelle_"
  settings.secret = ENV["COOKIE_SESSION_SECRET"]? || "4f74c0b358d5bab4000dd3c75465dc2c"
  # HTTPS only:
  settings.secure = PROD
end

APP_NAME = "Server-Dispatch"
VERSION  = "1.0.0"
