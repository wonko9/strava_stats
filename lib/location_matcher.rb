# frozen_string_literal: true

require 'yaml'
require_relative 'strava_stats/logging'

module StravaStats
  class LocationMatcher
    include Logging
    # Earth's radius in km
    EARTH_RADIUS_KM = 6371.0

    # Default matching radius in km
    DEFAULT_RADIUS_KM = 5.0

    # Winter sport types in Strava
    WINTER_SPORTS = %w[
      Snowboard
      AlpineSki
      BackcountrySki
      NordicSki
      Snowshoe
    ].freeze

    # Backcountry sport types that should be matched to peaks
    BACKCOUNTRY_SPORTS = %w[
      BackcountrySki
      Snowshoe
    ].freeze

    # Data file paths
    DATA_DIR = File.expand_path('../../data', __FILE__)
    RESORTS_FILE = File.join(DATA_DIR, 'resorts.yml')
    PEAKS_FILE = File.join(DATA_DIR, 'peaks.yml')

    def initialize(database:)
      @database = database
    end

    def seed_resorts_if_empty
      return if @database.get_resort_count.positive?

      logger.info "Seeding resort database..."
      seed_resorts
      logger.info "Seeded #{@database.get_resort_count} resorts"
    end

    def seed_peaks_if_empty
      return if @database.get_peak_count.positive?

      logger.info "Seeding peaks database..."
      seed_peaks
      logger.info "Seeded #{@database.get_peak_count} peaks"
    end

    def match_all_activities
      logger.info "\n=== Matching Activities to Resorts ==="

      # Clear existing matches
      @database.clear_activity_resorts

      activities = @database.get_all_activities
      resorts = @database.get_all_resorts

      matched = 0
      winter_count = 0

      activities.each do |activity|
        next unless WINTER_SPORTS.include?(activity['sport_type'])

        winter_count += 1
        lat = activity['start_lat']
        lng = activity['start_lng']

        next unless lat && lng

        # Find nearest resort within radius
        match = find_nearest_resort(lat, lng, resorts)

        if match
          @database.link_activity_to_resort(
            activity_id: activity['id'],
            resort_id: match[:resort]['id'],
            distance_km: match[:distance],
            matched_by: 'gps'
          )
          matched += 1
        end
      end

      logger.info "Matched #{matched}/#{winter_count} winter activities to resorts"

      # Also match backcountry activities to peaks
      match_backcountry_to_peaks

      matched
    end

    def match_backcountry_to_peaks
      # Clear existing peak matches
      @database.clear_activity_peaks

      activities = @database.get_all_activities
      peaks = @database.get_all_peaks

      return if peaks.empty?

      matched = 0
      backcountry_count = 0

      activities.each do |activity|
        next unless BACKCOUNTRY_SPORTS.include?(activity['sport_type'])

        backcountry_count += 1
        lat = activity['start_lat']
        lng = activity['start_lng']

        next unless lat && lng

        # Find nearest peak within radius
        match = find_nearest_peak(lat, lng, peaks)

        if match
          @database.link_activity_to_peak(
            activity_id: activity['id'],
            peak_id: match[:peak]['id'],
            distance_km: match[:distance]
          )
          matched += 1
        end
      end

      logger.info "Matched #{matched}/#{backcountry_count} backcountry activities to peaks" if backcountry_count > 0
      matched
    end

    def find_nearest_peak(lat, lng, peaks = nil)
      peaks ||= @database.get_all_peaks

      nearest = nil
      min_distance = Float::INFINITY

      peaks.each do |peak|
        distance = haversine_distance(
          lat, lng,
          peak['latitude'], peak['longitude']
        )

        radius = peak['radius_km'] || 2.0

        next unless distance <= radius && distance < min_distance

        min_distance = distance
        nearest = { peak: peak, distance: distance }
      end

      nearest
    end

    def find_nearest_resort(lat, lng, resorts = nil)
      resorts ||= @database.get_all_resorts

      nearest = nil
      min_distance = Float::INFINITY

      resorts.each do |resort|
        distance = haversine_distance(
          lat, lng,
          resort['latitude'], resort['longitude']
        )

        radius = resort['radius_km'] || DEFAULT_RADIUS_KM

        next unless distance <= radius && distance < min_distance

        min_distance = distance
        nearest = { resort: resort, distance: distance }
      end

      nearest
    end

    private

    def haversine_distance(lat1, lng1, lat2, lng2)
      # Convert to radians
      lat1_rad = lat1 * Math::PI / 180
      lat2_rad = lat2 * Math::PI / 180
      delta_lat = (lat2 - lat1) * Math::PI / 180
      delta_lng = (lng2 - lng1) * Math::PI / 180

      a = Math.sin(delta_lat / 2)**2 +
          Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(delta_lng / 2)**2

      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      EARTH_RADIUS_KM * c
    end

    def seed_resorts
      resorts = load_resorts_data
      resorts.each do |resort|
        @database.insert_resort(symbolize_keys(resort))
      end
    end

    def seed_peaks
      peaks = load_peaks_data
      peaks.each do |peak|
        @database.insert_peak(symbolize_keys(peak))
      end
    end

    def load_resorts_data
      return [] unless File.exist?(RESORTS_FILE)

      YAML.load_file(RESORTS_FILE) || []
    end

    def load_peaks_data
      return [] unless File.exist?(PEAKS_FILE)

      YAML.load_file(PEAKS_FILE) || []
    end

    def symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
