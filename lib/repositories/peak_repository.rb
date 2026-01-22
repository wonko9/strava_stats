# frozen_string_literal: true

module StravaStats
  module Repositories
    # Repository for peak and activity-peak relationship data.
    class PeakRepository
      def initialize(database)
        @db = database
      end

      def all
        @db.get_all_peaks
      end

      def count
        @db.get_peak_count
      end

      def insert(peak)
        @db.insert_peak(peak)
      end

      def for_activity(activity_id)
        @db.get_peak_for_activity(activity_id)
      end

      def for_activities(activity_ids)
        @db.get_peaks_for_activities(activity_ids)
      end

      def activities_for(peak_id)
        @db.get_activities_for_peak(peak_id)
      end

      def link_activity(activity_id:, peak_id:, distance_km:)
        @db.link_activity_to_peak(
          activity_id: activity_id,
          peak_id: peak_id,
          distance_km: distance_km
        )
      end

      def clear_activity_links
        @db.clear_activity_peaks
      end
    end
  end
end
