# frozen_string_literal: true

require_relative 'formatters'

module StravaStats
  module HTML
    # Transforms statistics data into Chart.js-compatible format.
    class ChartDataBuilder
      include Formatters

      # Unit conversion constants (same as StatsCalculator)
      METERS_TO_MILES = 0.000621371
      METERS_TO_FEET = 3.28084
      SECONDS_TO_HOURS = 1.0 / 3600

      def prepare_by_year_chart(by_year)
        return { labels: [], datasets: [] } unless by_year&.any?

        {
          labels: by_year.keys,
          datasets: [{
            label: 'Activities',
            data: by_year.values.map { |s| s[:total_activities] },
            backgroundColor: '#FC4C02'
          }]
        }
      end

      def prepare_by_sport_chart(by_sport)
        return { labels: [], datasets: [] } unless by_sport&.any?

        # Sort by activity count and take top entries
        sorted = by_sport.sort_by { |_, stats| -stats[:total_activities] }

        {
          labels: sorted.map { |sport, _| format_sport_name(sport) },
          datasets: [{
            data: sorted.map { |_, stats| stats[:total_activities] },
            backgroundColor: sorted.map { |sport, _| sport_color(sport) }
          }]
        }
      end

      def prepare_sport_by_year_charts(by_sport_and_year)
        return {} unless by_sport_and_year&.any?

        by_sport_and_year.transform_values do |years|
          {
            labels: years.keys.sort,
            datasets: [{
              label: 'Activities',
              data: years.keys.sort.map { |year| years[year][:total_activities] },
              backgroundColor: '#FC4C02'
            }]
          }
        end
      end

      def prepare_winter_season_chart(winter_by_season)
        return { labels: [], datasets: [] } unless winter_by_season&.any?

        seasons = winter_by_season.keys.sort
        sports = winter_by_season.values.flat_map { |d| d[:by_sport].keys }.uniq.sort

        {
          labels: seasons,
          datasets: sports.map do |sport|
            {
              label: format_sport_name(sport),
              data: seasons.map { |s| winter_by_season.dig(s, :by_sport, sport, :total_activities) || 0 },
              backgroundColor: sport_color(sport)
            }
          end
        }
      end

      # Collect all activities from various stat sources and deduplicate
      def collect_all_activities(stats)
        activities = {}

        # From by_sport
        stats[:by_sport]&.each_value do |sport_data|
          sport_data[:activities]&.each do |a|
            activities[a[:id]] ||= normalize_activity(a)
          end
        end

        # From by_year
        stats[:by_year]&.each_value do |year_data|
          year_data[:activities]&.each do |a|
            activities[a[:id]] ||= normalize_activity(a)
          end
        end

        # From resorts_by_season
        stats[:resorts_by_season]&.each_value do |resorts|
          resorts.each_value do |resort_data|
            resort_data[:activities]&.each do |a|
              activities[a['id']] ||= normalize_raw_activity(a)
            end
          end
        end

        # From peaks_by_season
        stats[:peaks_by_season]&.each_value do |peaks|
          peaks.each_value do |peak_data|
            peak_data[:activities]&.each do |a|
              activities[a['id']] ||= normalize_raw_activity(a)
            end
          end
        end

        activities
      end

      private

      # Normalize activity summary format (from calculate_sport_stats)
      def normalize_activity(a)
        {
          id: a[:id],
          name: a[:name] || 'Activity',
          date: a[:date],
          elevation: a[:elevation],
          hours: a[:hours],
          miles: a[:miles],
          calories: a[:calories]
        }
      end

      # Normalize raw activity format (from database)
      def normalize_raw_activity(a)
        {
          id: a['id'],
          name: a['name'] || 'Activity',
          date: a['start_date_local']&.split('T')&.first || '',
          elevation: ((a['total_elevation_gain'] || 0) * METERS_TO_FEET).round(0),
          hours: ((a['moving_time'] || 0) * SECONDS_TO_HOURS).round(2),
          miles: ((a['distance'] || 0) * METERS_TO_MILES).round(1),
          calories: (a['calories'] || 0).round(0)
        }
      end
    end
  end
end
