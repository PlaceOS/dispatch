require "placeos-log-backend"
require "./constants"

# Logging configuration
module App::Logging
  ::Log.progname = App::APP_NAME

  log_backend = PlaceOS::LogBackend.log_backend
  log_level = App.running_in_production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  namespaces = ["action-controller.*", "place_os.*", "#{App::APP_NAME}.*"]

  builder = ::Log.builder
  builder.bind "*", log_level, log_backend

  namespaces.each do |namespace|
    builder.bind namespace, log_level, log_backend
  end

  ::Log.setup_from_env(
    default_level: log_level,
    builder: builder,
    backend: log_backend,
    log_level_env: "LOG_LEVEL",
  )

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: App.running_in_production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
