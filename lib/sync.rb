# frozen_string_literal: true

require 'time'
require_relative 'strava_stats/logging'

module StravaStats
  class Sync
    include Logging
    # Strava rate limits: 100 requests per 15 minutes, 1000 per day
    # At 2 sec delay, we can fetch ~100 activities in ~3.5 minutes before hitting limit
    RATE_LIMIT_DELAY = 2.0  # seconds between detailed requests

    def initialize(api:, activities:, auth:, on_progress: nil)
      @api = api
      @activities = activities
      @auth = auth
      @on_progress = on_progress  # Callback to regenerate HTML
    end

    def sync_activities(full: false)
      logger.info "\n=== Syncing Activities ==="

      # Show current status
      current_count = @activities.count
      without_details = @activities.without_details_count
      logger.info "Currently synced: #{current_count} activities"
      logger.info "Missing details: #{without_details}" if without_details > 0

      last_sync = full ? nil : @auth.last_sync_at
      sync_start_time = Time.now.to_i

      if last_sync
        last_sync_time = Time.at(last_sync)
        logger.info "Last sync: #{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}"
        logger.info "\nFetching new activities since then..."
      else
        logger.info "\nFull sync - fetching all activities..."
      end

      # Step 1: Fetch activity list (summaries)
      count = 0
      begin
        @api.get_all_activities(after: last_sync) do |activity|
          @activities.save(activity, details_fetched: false)
          count += 1
          print "\r  Fetched #{count} activity summaries..."
        end
      rescue StravaStats::RateLimitError => e
        logger.warn "\n\nRate limit hit while fetching activity list! #{e.message}"
        trigger_progress_callback  # Generate HTML with current progress
        logger.info "   Waiting 15 minutes before resuming... (#{Time.now.strftime('%H:%M:%S')})"
        logger.info "   Progress is saved - you can also Ctrl+C and run 'sync' later to resume.\n"
        countdown_wait(e.wait_seconds)
        retry
      rescue StravaStats::DailyLimitError => e
        logger.error "\n\n#{e.message}"
        logger.info "   Progress saved. Run 'strava_stats sync' tomorrow to continue."
        trigger_progress_callback  # Generate HTML with current progress
      end

      if count > 0
        logger.info "\nFetched #{count} new activity summaries"
      else
        logger.info "\nNo new activities to sync"
      end

      # Update last sync timestamp
      @auth.update_last_sync_at(sync_start_time)

      # Step 2: Fetch detailed data for activities missing details (newest first)
      fetch_missing_details

      total = @activities.count
      remaining_details = @activities.without_details_count
      logger.info "\n=== Sync Complete ==="
      logger.info "Total activities: #{total}"
      logger.info "Still need details: #{remaining_details}" if remaining_details > 0

      # Generate final HTML
      trigger_progress_callback

      count
    end

    def refresh_activities(activity_ids)
      logger.info "\n=== Refreshing Activities ==="
      logger.info "Refreshing #{activity_ids.count} activity(ies)...\n"

      refreshed = 0
      activity_ids.each_with_index do |activity_id, index|
        print "  [#{index + 1}/#{activity_ids.count}] Fetching #{activity_id}..."

        begin
          detailed = @api.get_activity(activity_id)
          @activities.save(detailed, details_fetched: true)
          logger.info " #{detailed['name']} (#{detailed['sport_type']})"
          refreshed += 1
        rescue StravaStats::RateLimitError => e
          logger.warn "\n\nRate limit hit! #{e.message}"
          countdown_wait(e.wait_seconds)
          retry
        rescue StandardError => e
          logger.error " Error: #{e.message}"
        end

        sleep(RATE_LIMIT_DELAY) if index < activity_ids.count - 1
      end

      logger.info "\nRefreshed #{refreshed} activity(ies)"

      # Regenerate HTML
      trigger_progress_callback

      refreshed
    end

    def fetch_missing_details
      pending = @activities.without_details
      return if pending.empty?

      logger.info "\n=== Fetching Activity Details (for calories, etc.) ==="
      logger.info "#{pending.count} activities need details..."
      logger.info "This may take a while due to API rate limits.\n"

      fetched = 0
      pending.each_with_index do |activity, index|
        activity_id = activity['id']
        activity_date = activity['start_date_local']&.split('T')&.first || 'unknown date'
        activity_name = activity['name'] || 'Untitled'

        print "\r  [#{index + 1}/#{pending.count}] #{activity_date}: #{activity_name[0..40].ljust(41)}..."

        begin
          detailed = @api.get_activity(activity_id)
          @activities.save(detailed, details_fetched: true)
          fetched += 1
        rescue StravaStats::RateLimitError => e
          logger.warn "\n\nRate limit hit! #{e.message}"
          trigger_progress_callback  # Generate HTML with current progress
          logger.info "   Waiting 15 minutes before resuming... (#{Time.now.strftime('%H:%M:%S')})"
          logger.info "   Progress is saved - you can also Ctrl+C and run 'sync' later to resume.\n"
          countdown_wait(e.wait_seconds)
          retry
        rescue StravaStats::DailyLimitError => e
          logger.error "\n\n#{e.message}"
          logger.info "   Progress saved. Run 'strava_stats sync' tomorrow to continue."
          logger.info "   Fetched #{fetched} activities before hitting limit."
          trigger_progress_callback  # Generate HTML with current progress
          return fetched
        rescue StandardError => e
          logger.warn "\n    Failed to fetch details for #{activity_id}: #{e.message}"
        end

        # Rate limiting - be conservative to avoid hitting limits
        sleep(RATE_LIMIT_DELAY) if index < pending.count - 1
      end

      logger.info "\nFetched details for #{fetched} activities"
      fetched
    end

    def sync_status
      last_sync = @auth.last_sync_at
      total = @activities.count
      newest = @activities.newest_date
      without_details = @activities.without_details_count

      {
        last_sync: last_sync ? Time.at(last_sync) : nil,
        total_activities: total,
        newest_activity: newest ? Time.parse(newest) : nil,
        without_details: without_details
      }
    end

    private

    def trigger_progress_callback
      return unless @on_progress

      @on_progress.call
    rescue StandardError => e
      logger.warn "   Failed to generate HTML: #{e.message}"
    end

    def countdown_wait(seconds)
      end_time = Time.now + seconds
      while Time.now < end_time
        remaining = (end_time - Time.now).to_i
        mins, secs = remaining.divmod(60)
        print "\r   Resuming in #{mins}:#{secs.to_s.rjust(2, '0')}...  "
        sleep(1)
      end
      logger.info "\r   Resuming now!                    "
    end
  end
end
