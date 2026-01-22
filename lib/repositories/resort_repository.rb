# frozen_string_literal: true

module StravaStats
  module Repositories
    # Repository for resort and activity-resort relationship data.
    class ResortRepository
      def initialize(database)
        @db = database
      end

      def all
        @db.get_all_resorts
      end

      def count
        @db.get_resort_count
      end

      def insert(resort)
        @db.insert_resort(resort)
      end

      def for_activity(activity_id)
        @db.get_resort_for_activity(activity_id)
      end

      def for_activities(activity_ids)
        @db.get_resorts_for_activities(activity_ids)
      end

      def activities_for(resort_id)
        @db.get_activities_for_resort(resort_id)
      end

      def link_activity(activity_id:, resort_id:, distance_km:, matched_by:)
        @db.link_activity_to_resort(
          activity_id: activity_id,
          resort_id: resort_id,
          distance_km: distance_km,
          matched_by: matched_by
        )
      end

      def clear_activity_links
        @db.clear_activity_resorts
      end
    end
  end
end
