# frozen_string_literal: true

module StravaStats
  module Repositories
    # Repository for activity data access.
    # Provides domain-focused methods for querying and persisting activities.
    class ActivityRepository
      def initialize(database)
        @db = database
      end

      def all(include_ignored: false)
        @db.get_all_activities(include_ignored: include_ignored)
      end

      def find(id)
        @db.get_activity(id)
      end

      def by_sport(sport_type)
        @db.get_activities_by_sport(sport_type)
      end

      def without_details
        @db.get_activities_without_details
      end

      def without_details_count
        @db.get_activities_without_details_count
      end

      def count
        @db.get_activity_count
      end

      def newest_date
        @db.get_newest_activity_date
      end

      def ignored
        @db.get_ignored_activities
      end

      def save(activity, details_fetched: false)
        @db.upsert_activity(activity, details_fetched: details_fetched)
      end

      def ignore(id)
        @db.ignore_activity(id)
      end

      def unignore(id)
        @db.unignore_activity(id)
      end
    end
  end
end
