# Application dependencies
require "action-controller"
require "active-model"
require "./constants"
require "log_helper"

# Configure logging (backend defined in constants.cr)
if App.running_in_production?
  log_level = Log::Severity::Info
  Log.builder.bind "*", :warning, App::LOG_BACKEND
else
  log_level = Log::Severity::Debug
  Log.builder.bind "*", :info, App::LOG_BACKEND
end
Log.builder.bind "action-controller.*", log_level, App::LOG_BACKEND
Log.builder.bind "#{App::NAME}.*", log_level, App::LOG_BACKEND

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]
keeps_headers = ["X-Request-ID"]

# Application code
require "./controllers/application"
require "./controllers/*"
require "./models/*"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(App.running_in_production?, keeps_headers),
  ActionController::LogHandler.new(filter_params)
)
