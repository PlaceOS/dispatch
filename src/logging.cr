require "placeos-log-backend"

require "./constants"

# Logging configuration
module App::Logging
  ::Log.progname = App::NAME

  log_backend = PlaceOS::LogBackend.log_backend
  log_level = App.running_in_production? ? ::Log::Severity::Info : ::Log::Severity::Debug
  namespaces = ["action-controller.*", "place_os.*", "#{App::NAME}.*"]

  ::Log.setup do |config|
    config.bind "*", :warn, log_backend

    namespaces.each do |namespace|
      config.bind namespace, log_level, log_backend
    end
  end

  PlaceOS::LogBackend.register_severity_switch_signals(
    production: App.running_in_production?,
    namespaces: namespaces,
    backend: log_backend,
  )
end
