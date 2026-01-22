# frozen_string_literal: true

require 'logger'

module StravaStats
  # Logging module that can be included in any class for structured logging.
  # Uses Ruby's stdlib Logger with a clean, minimal output format.
  #
  # Usage:
  #   class MyClass
  #     include StravaStats::Logging
  #
  #     def some_method
  #       logger.info "Processing..."
  #       logger.debug "Detailed info" if ENV['DEBUG']
  #     end
  #   end
  #
  module Logging
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def logger
        StravaStats.logger
      end
    end

    def logger
      StravaStats.logger
    end
  end

  class << self
    attr_writer :logger

    def logger
      @logger ||= default_logger
    end

    private

    def default_logger
      Logger.new($stdout).tap do |log|
        log.progname = 'strava_stats'
        log.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
        log.formatter = proc do |severity, _datetime, _progname, msg|
          case severity
          when 'INFO'
            "#{msg}\n"
          when 'DEBUG'
            "[DEBUG] #{msg}\n"
          when 'WARN'
            "Warning: #{msg}\n"
          when 'ERROR'
            "Error: #{msg}\n"
          else
            "#{msg}\n"
          end
        end
      end
    end
  end
end
