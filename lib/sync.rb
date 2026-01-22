# frozen_string_literal: true

require 'time'

module StravaStats
  class Sync
    # Strava rate limits: 100 requests per 15 minutes, 1000 per day
    # At 2 sec delay, we can fetch ~100 activities in ~3.5 minutes before hitting limit
    RATE_LIMIT_DELAY = 2.0  # seconds between detailed requests

    def initialize(api:, database:, on_progress: nil)
      @api = api
      @database = database
      @on_progress = on_progress  # Callback to regenerate HTML
    end

    def sync_activities(full: false)
      puts "\n=== Syncing Activities ==="

      # Show current status
      current_count = @database.get_activity_count
      without_details = @database.get_activities_without_details_count
      puts "Currently synced: #{current_count} activities"
      puts "Missing details: #{without_details}" if without_details > 0

      last_sync = full ? nil : @database.get_last_sync_at
      sync_start_time = Time.now.to_i

      if last_sync
        last_sync_time = Time.at(last_sync)
        puts "Last sync: #{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}"
        puts "\nFetching new activities since then..."
      else
        puts "\nFull sync - fetching all activities..."
      end

      # Step 1: Fetch activity list (summaries)
      count = 0
      begin
        @api.get_all_activities(after: last_sync) do |activity|
          @database.upsert_activity(activity, details_fetched: false)
          count += 1
          print "\r  Fetched #{count} activity summaries..."
        end
      rescue StravaStats::RateLimitError => e
        puts "\n\n⏳ Rate limit hit while fetching activity list! #{e.message}"
        trigger_progress_callback  # Generate HTML with current progress
        puts "   Waiting 15 minutes before resuming... (#{Time.now.strftime('%H:%M:%S')})"
        puts "   Progress is saved - you can also Ctrl+C and run 'sync' later to resume.\n"
        countdown_wait(e.wait_seconds)
        retry
      rescue StravaStats::DailyLimitError => e
        puts "\n\n⛔ #{e.message}"
        puts "   Progress saved. Run 'strava_stats sync' tomorrow to continue."
        trigger_progress_callback  # Generate HTML with current progress
      end

      if count > 0
        puts "\n✓ Fetched #{count} new activity summaries"
      else
        puts "\n✓ No new activities to sync"
      end

      # Update last sync timestamp
      @database.set_last_sync_at(sync_start_time)

      # Step 2: Fetch detailed data for activities missing details (newest first)
      fetch_missing_details

      total = @database.get_activity_count
      remaining_details = @database.get_activities_without_details_count
      puts "\n=== Sync Complete ==="
      puts "Total activities: #{total}"
      puts "Still need details: #{remaining_details}" if remaining_details > 0

      # Generate final HTML
      trigger_progress_callback

      count
    end

    def refresh_activities(activity_ids)
      puts "\n=== Refreshing Activities ==="
      puts "Refreshing #{activity_ids.count} activity(ies)...\n"

      refreshed = 0
      activity_ids.each_with_index do |activity_id, index|
        print "  [#{index + 1}/#{activity_ids.count}] Fetching #{activity_id}..."

        begin
          detailed = @api.get_activity(activity_id)
          @database.upsert_activity(detailed, details_fetched: true)
          puts " #{detailed['name']} (#{detailed['sport_type']})"
          refreshed += 1
        rescue StravaStats::RateLimitError => e
          puts "\n\n⏳ Rate limit hit! #{e.message}"
          countdown_wait(e.wait_seconds)
          retry
        rescue StandardError => e
          puts " Error: #{e.message}"
        end

        sleep(RATE_LIMIT_DELAY) if index < activity_ids.count - 1
      end

      puts "\n✓ Refreshed #{refreshed} activity(ies)"

      # Regenerate HTML
      trigger_progress_callback

      refreshed
    end

    def fetch_missing_details
      activities = @database.get_activities_without_details
      return if activities.empty?

      puts "\n=== Fetching Activity Details (for calories, etc.) ==="
      puts "#{activities.count} activities need details..."
      puts "This may take a while due to API rate limits.\n"

      fetched = 0
      activities.each_with_index do |activity, index|
        activity_id = activity['id']
        activity_date = activity['start_date_local']&.split('T')&.first || 'unknown date'
        activity_name = activity['name'] || 'Untitled'

        print "\r  [#{index + 1}/#{activities.count}] #{activity_date}: #{activity_name[0..40].ljust(41)}..."

        begin
          detailed = @api.get_activity(activity_id)
          @database.upsert_activity(detailed, details_fetched: true)
          fetched += 1
        rescue StravaStats::RateLimitError => e
          puts "\n\n⏳ Rate limit hit! #{e.message}"
          trigger_progress_callback  # Generate HTML with current progress
          puts "   Waiting 15 minutes before resuming... (#{Time.now.strftime('%H:%M:%S')})"
          puts "   Progress is saved - you can also Ctrl+C and run 'sync' later to resume.\n"
          countdown_wait(e.wait_seconds)
          retry
        rescue StravaStats::DailyLimitError => e
          puts "\n\n⛔ #{e.message}"
          puts "   Progress saved. Run 'strava_stats sync' tomorrow to continue."
          puts "   Fetched #{fetched} activities before hitting limit."
          trigger_progress_callback  # Generate HTML with current progress
          return fetched
        rescue StandardError => e
          puts "\n    Warning: Failed to fetch details for #{activity_id}: #{e.message}"
        end

        # Rate limiting - be conservative to avoid hitting limits
        sleep(RATE_LIMIT_DELAY) if index < activities.count - 1
      end

      puts "\n✓ Fetched details for #{fetched} activities"
      fetched
    end

    private

    def trigger_progress_callback
      return unless @on_progress

      @on_progress.call
    rescue StandardError => e
      puts "   Warning: Failed to generate HTML: #{e.message}"
    end

    def countdown_wait(seconds)
      end_time = Time.now + seconds
      while Time.now < end_time
        remaining = (end_time - Time.now).to_i
        mins, secs = remaining.divmod(60)
        print "\r   Resuming in #{mins}:#{secs.to_s.rjust(2, '0')}...  "
        sleep(1)
      end
      puts "\r   Resuming now!                    "
    end

    def sync_status
      last_sync = @database.get_last_sync_at
      total = @database.get_activity_count
      newest = @database.get_newest_activity_date
      without_details = @database.get_activities_without_details_count

      {
        last_sync: last_sync ? Time.at(last_sync) : nil,
        total_activities: total,
        newest_activity: newest ? Time.parse(newest) : nil,
        without_details: without_details
      }
    end
  end
end
