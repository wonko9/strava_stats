# frozen_string_literal: true

require 'fileutils'
require_relative '../repositories/activity_repository'
require_relative '../repositories/resort_repository'
require_relative '../repositories/peak_repository'
require_relative '../repositories/auth_repository'

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

    # Repositories
    def activities
      @instances[:activities] ||= Repositories::ActivityRepository.new(database)
    end

    def resorts
      @instances[:resorts] ||= Repositories::ResortRepository.new(database)
    end

    def peaks
      @instances[:peaks] ||= Repositories::PeakRepository.new(database)
    end

    def auth
      @instances[:auth] ||= Repositories::AuthRepository.new(database)
    end

    def api
      @instances[:api] ||= build_api
    end

    def location_matcher
      @instances[:location_matcher] ||= LocationMatcher.new(
        database: database,
        resorts: resorts,
        peaks: peaks,
        activities: activities
      )
    end

    def stats_calculator
      @instances[:stats_calculator] ||= StatsCalculator.new(
        activities: activities,
        resorts: resorts,
        peaks: peaks
      )
    end

    def html_generator
      @instances[:html_generator] ||= HTMLGenerator.new(
        output_path: output_path
      )
    end

    def syncer(on_progress: nil)
      @instances[:syncer] ||= Sync.new(
        api: api,
        activities: activities,
        auth: auth,
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
        auth: auth,
        callback_port: @config.dig('oauth', 'callback_port') || 8888
      )
    end
  end
end
