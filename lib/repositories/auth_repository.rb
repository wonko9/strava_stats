# frozen_string_literal: true

module StravaStats
  module Repositories
    # Repository for authentication tokens and sync state.
    class AuthRepository
      def initialize(database)
        @db = database
      end

      # Token management
      def save_tokens(access_token:, refresh_token:, expires_at:, athlete: nil)
        @db.save_tokens(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at,
          athlete: athlete
        )
      end

      def get_tokens
        @db.get_tokens
      end

      # Sync state
      def last_sync_at
        @db.get_last_sync_at
      end

      def update_last_sync_at(timestamp)
        @db.set_last_sync_at(timestamp)
      end
    end
  end
end
