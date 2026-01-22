# frozen_string_literal: true

require_relative 'logging'

module StravaStats
  # Application service layer that orchestrates multi-step operations.
  # Consolidates duplicated orchestration logic from CLI commands.
  class Application
    include Logging

    def initialize(factory)
      @factory = factory
    end

    # Generate HTML stats page with location matching and stats calculation.
    # @param verbose [Boolean] whether to log progress messages
    # @return [String, nil] output path if successful, nil otherwise
    def generate_html(verbose: true)
      count = @factory.database.get_activity_count
      if count.zero?
        logger.warn 'No activities in database. Run "strava_stats sync" first.' if verbose
        return nil
      end

      logger.info "\n=== Generating Stats ===" if verbose
      logger.info "Processing #{count} activities..." if verbose

      ensure_locations_matched

      stats = @factory.stats_calculator.calculate_all_stats
      athlete_name = fetch_athlete_name

      @factory.html_generator.generate(stats: stats, athlete_name: athlete_name)
    end

    # Generate HTML quietly (for progress callbacks during sync).
    # Suppresses most output and swallows errors.
    def generate_html_quietly
      return if @factory.database.get_activity_count.zero?

      ensure_locations_matched
      stats = @factory.stats_calculator.calculate_all_stats
      athlete_name = fetch_athlete_name
      @factory.html_generator.generate(stats: stats, athlete_name: athlete_name)
    rescue StandardError => e
      logger.warn "Failed to generate HTML: #{e.message}"
    end

    # Ensure all resort and peak locations are seeded and activities are matched.
    # This is called before generating HTML to ensure location data is current.
    def ensure_locations_matched
      matcher = @factory.location_matcher
      matcher.seed_resorts_if_empty
      matcher.seed_peaks_if_empty
      matcher.match_all_activities
    end

    # Create a syncer with a progress callback that regenerates HTML.
    # @return [Sync] configured syncer instance
    def syncer_with_progress
      @factory.syncer(on_progress: -> { generate_html_quietly })
    end

    # Fetch athlete's first name from stored tokens.
    # @return [String, nil] athlete's first name or nil
    def fetch_athlete_name
      tokens = @factory.database.get_tokens
      tokens&.dig(:athlete, 'firstname')
    end
  end
end
