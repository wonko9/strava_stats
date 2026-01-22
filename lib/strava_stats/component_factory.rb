# frozen_string_literal: true

require 'fileutils'

module StravaStats
  # Factory for creating and wiring application components.
  # Provides lazy-loaded, memoized instances of all major components.
  class ComponentFactory
    def initialize(config)
      @config = config
      @instances = {}
    end

    def database
      @instances[:database] ||= build_database
    end

    def api
      @instances[:api] ||= build_api
    end

    def location_matcher
      @instances[:location_matcher] ||= LocationMatcher.new(database: database)
    end

    def stats_calculator
      @instances[:stats_calculator] ||= StatsCalculator.new(database: database)
    end

    def html_generator
      @instances[:html_generator] ||= HTMLGenerator.new(
        output_path: output_path
      )
    end

    def syncer(on_progress: nil)
      @instances[:syncer] ||= Sync.new(
        api: api,
        database: database,
        on_progress: on_progress
      )
    end

    def output_path
      @config.dig('output', 'path') || 'output/index.html'
    end

    private

    def build_database
      db_path = @config.dig('database', 'path') || 'data/strava_stats.db'
      FileUtils.mkdir_p(File.dirname(db_path))
      Database.new(db_path)
    end

    def build_api
      StravaAPI.new(
        client_id: @config.dig('strava', 'client_id'),
        client_secret: @config.dig('strava', 'client_secret'),
        database: database,
        callback_port: @config.dig('oauth', 'callback_port') || 8888
      )
    end
  end
end
