# frozen_string_literal: true

module StravaStats
  module HTML
    # Shared formatting utilities and color constants for HTML generation.
    module Formatters
      SPORT_COLORS = {
        'Run' => '#FC4C02',
        'Ride' => '#2D73F5',
        'Swim' => '#00D4FF',
        'Walk' => '#7CB342',
        'Hike' => '#8D6E63',
        'Snowboard' => '#9C27B0',
        'AlpineSki' => '#E91E63',
        'BackcountrySki' => '#FF5722',
        'NordicSki' => '#00BCD4',
        'Snowshoe' => '#607D8B',
        'Workout' => '#FF9800',
        'WeightTraining' => '#795548',
        'Yoga' => '#4CAF50',
        'VirtualRide' => '#3F51B5',
        'VirtualRun' => '#F44336',
        'EBikeRide' => '#009688',
        'MountainBikeRide' => '#673AB7',
        'GravelRide' => '#CDDC39',
        'Kayaking' => '#03A9F4',
        'Rowing' => '#8BC34A',
        'StandUpPaddling' => '#00ACC1',
        'Surfing' => '#26C6DA',
        'Windsurf' => '#4DD0E1',
        'Kitesurf' => '#80DEEA',
        'Golf' => '#AED581',
        'RockClimbing' => '#FF7043',
        'IceSkate' => '#B3E5FC',
        'Crossfit' => '#FFAB00',
        'Elliptical' => '#FFD54F',
        'StairStepper' => '#FFC107'
      }.freeze

      DEFAULT_COLOR = '#9E9E9E'

      def sport_color(sport)
        SPORT_COLORS[sport] || DEFAULT_COLOR
      end

      def format_sport_name(sport)
        return '' unless sport

        sport.gsub(/([a-z])([A-Z])/, '\1 \2')
      end

      def format_number(num)
        return '0' unless num

        if num.is_a?(Float)
          formatted = num.round(1).to_s
          parts = formatted.split('.')
          parts[0] = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          parts.join('.')
        else
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end

      def format_date(date_str)
        return '' unless date_str

        Time.parse(date_str).strftime('%b %d, %Y')
      rescue ArgumentError
        date_str
      end
    end
  end
end
