# frozen_string_literal: true

require 'sqlite3'
require 'json'

module StravaStats
  class Database
    SCHEMA_VERSION = 1

    def initialize(db_path)
      @db_path = db_path
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      setup_schema
    end

    def setup_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS schema_info (
          version INTEGER PRIMARY KEY
        );

        CREATE TABLE IF NOT EXISTS sync_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          last_sync_at INTEGER,
          athlete_id INTEGER
        );

        CREATE TABLE IF NOT EXISTS activities (
          id INTEGER PRIMARY KEY,
          athlete_id INTEGER NOT NULL,
          name TEXT,
          description TEXT,
          sport_type TEXT,
          activity_type TEXT,
          start_date TEXT,
          start_date_local TEXT,
          timezone TEXT,
          elapsed_time INTEGER,
          moving_time INTEGER,
          distance REAL,
          total_elevation_gain REAL,
          elev_high REAL,
          elev_low REAL,
          calories REAL,
          start_lat REAL,
          start_lng REAL,
          end_lat REAL,
          end_lng REAL,
          average_speed REAL,
          max_speed REAL,
          average_heartrate REAL,
          max_heartrate REAL,
          suffer_score INTEGER,
          -- Power data
          average_watts REAL,
          max_watts REAL,
          weighted_average_watts REAL,
          kilojoules REAL,
          device_watts INTEGER,
          -- Cadence/temp
          average_cadence REAL,
          average_temp REAL,
          -- Gear
          gear_id TEXT,
          gear_name TEXT,
          -- Device
          device_name TEXT,
          -- Flags
          trainer INTEGER,
          commute INTEGER,
          manual INTEGER,
          private INTEGER,
          flagged INTEGER,
          -- Counts
          pr_count INTEGER,
          achievement_count INTEGER,
          kudos_count INTEGER,
          comment_count INTEGER,
          photo_count INTEGER,
          -- Workout
          workout_type INTEGER,
          perceived_exertion INTEGER,
          -- Location
          location_city TEXT,
          location_state TEXT,
          location_country TEXT,
          -- Map
          map_polyline TEXT,
          map_summary_polyline TEXT,
          -- Complex data (stored as JSON)
          splits_metric TEXT,
          splits_standard TEXT,
          laps TEXT,
          segment_efforts TEXT,
          best_efforts TEXT,
          -- Meta
          raw_json TEXT,
          details_fetched INTEGER DEFAULT 0,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_activities_sport_type ON activities(sport_type);
        CREATE INDEX IF NOT EXISTS idx_activities_start_date ON activities(start_date);
        CREATE INDEX IF NOT EXISTS idx_activities_start_lat_lng ON activities(start_lat, start_lng);

        CREATE TABLE IF NOT EXISTS resorts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          country TEXT,
          region TEXT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          radius_km REAL DEFAULT 5.0,
          resort_type TEXT DEFAULT 'resort',
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_resorts_lat_lng ON resorts(latitude, longitude);

        CREATE TABLE IF NOT EXISTS activity_resorts (
          activity_id INTEGER NOT NULL,
          resort_id INTEGER NOT NULL,
          distance_km REAL,
          matched_by TEXT,
          PRIMARY KEY (activity_id, resort_id),
          FOREIGN KEY (activity_id) REFERENCES activities(id),
          FOREIGN KEY (resort_id) REFERENCES resorts(id)
        );

        CREATE TABLE IF NOT EXISTS tokens (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          access_token TEXT,
          refresh_token TEXT,
          expires_at INTEGER,
          athlete_json TEXT
        );

        CREATE TABLE IF NOT EXISTS peaks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          country TEXT,
          region TEXT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          elevation_meters REAL,
          elevation_feet REAL,
          radius_km REAL DEFAULT 2.0,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_peaks_lat_lng ON peaks(latitude, longitude);

        CREATE TABLE IF NOT EXISTS activity_peaks (
          activity_id INTEGER NOT NULL,
          peak_id INTEGER NOT NULL,
          distance_km REAL,
          PRIMARY KEY (activity_id, peak_id),
          FOREIGN KEY (activity_id) REFERENCES activities(id),
          FOREIGN KEY (peak_id) REFERENCES peaks(id)
        );
      SQL

      # Initialize sync_state if not exists
      @db.execute('INSERT OR IGNORE INTO sync_state (id) VALUES (1)')

      # Migration: add details_fetched column if it doesn't exist
      migrate_add_details_fetched
    end

    def migrate_add_details_fetched
      columns = @db.execute("PRAGMA table_info(activities)").map { |c| c['name'] }

      # All columns that should exist (for migration from older schemas)
      migrations = {
        'details_fetched' => 'INTEGER DEFAULT 0',
        'description' => 'TEXT',
        'average_watts' => 'REAL',
        'max_watts' => 'REAL',
        'weighted_average_watts' => 'REAL',
        'kilojoules' => 'REAL',
        'device_watts' => 'INTEGER',
        'average_cadence' => 'REAL',
        'average_temp' => 'REAL',
        'gear_id' => 'TEXT',
        'gear_name' => 'TEXT',
        'device_name' => 'TEXT',
        'trainer' => 'INTEGER',
        'commute' => 'INTEGER',
        'manual' => 'INTEGER',
        'private' => 'INTEGER',
        'flagged' => 'INTEGER',
        'pr_count' => 'INTEGER',
        'achievement_count' => 'INTEGER',
        'kudos_count' => 'INTEGER',
        'comment_count' => 'INTEGER',
        'photo_count' => 'INTEGER',
        'workout_type' => 'INTEGER',
        'perceived_exertion' => 'INTEGER',
        'map_polyline' => 'TEXT',
        'map_summary_polyline' => 'TEXT',
        'splits_metric' => 'TEXT',
        'splits_standard' => 'TEXT',
        'laps' => 'TEXT',
        'segment_efforts' => 'TEXT',
        'best_efforts' => 'TEXT'
      }

      migrations.each do |col_name, col_type|
        next if columns.include?(col_name)

        @db.execute("ALTER TABLE activities ADD COLUMN #{col_name} #{col_type}")
      end
    end

    # Token management
    def save_tokens(access_token:, refresh_token:, expires_at:, athlete: nil)
      athlete_json = athlete ? JSON.generate(athlete) : nil
      @db.execute(
        'INSERT OR REPLACE INTO tokens (id, access_token, refresh_token, expires_at, athlete_json) VALUES (1, ?, ?, ?, ?)',
        [access_token, refresh_token, expires_at, athlete_json]
      )
    end

    def get_tokens
      row = @db.get_first_row('SELECT * FROM tokens WHERE id = 1')
      return nil unless row

      {
        access_token: row['access_token'],
        refresh_token: row['refresh_token'],
        expires_at: row['expires_at'],
        athlete: row['athlete_json'] ? JSON.parse(row['athlete_json']) : nil
      }
    end

    # Sync state management
    def get_last_sync_at
      row = @db.get_first_row('SELECT last_sync_at FROM sync_state WHERE id = 1')
      row&.fetch('last_sync_at', nil)
    end

    def set_last_sync_at(timestamp)
      @db.execute('UPDATE sync_state SET last_sync_at = ? WHERE id = 1', [timestamp])
    end

    # Activity management
    def upsert_activity(activity, details_fetched: false)
      start_latlng = activity['start_latlng'] || []
      end_latlng = activity['end_latlng'] || []

      # Extract gear name from nested object
      gear_name = activity.dig('gear', 'name')

      # Extract map polylines
      map_polyline = activity.dig('map', 'polyline')
      map_summary_polyline = activity.dig('map', 'summary_polyline')

      # Convert complex arrays to JSON strings
      splits_metric = activity['splits_metric'] ? JSON.generate(activity['splits_metric']) : nil
      splits_standard = activity['splits_standard'] ? JSON.generate(activity['splits_standard']) : nil
      laps = activity['laps'] ? JSON.generate(activity['laps']) : nil
      segment_efforts = activity['segment_efforts'] ? JSON.generate(activity['segment_efforts']) : nil
      best_efforts = activity['best_efforts'] ? JSON.generate(activity['best_efforts']) : nil

      @db.execute(<<~SQL, [
        INSERT OR REPLACE INTO activities (
          id, athlete_id, name, description, sport_type, activity_type,
          start_date, start_date_local, timezone,
          elapsed_time, moving_time, distance, total_elevation_gain,
          elev_high, elev_low, calories,
          start_lat, start_lng, end_lat, end_lng,
          average_speed, max_speed, average_heartrate, max_heartrate, suffer_score,
          average_watts, max_watts, weighted_average_watts, kilojoules, device_watts,
          average_cadence, average_temp,
          gear_id, gear_name, device_name,
          trainer, commute, manual, private, flagged,
          pr_count, achievement_count, kudos_count, comment_count, photo_count,
          workout_type, perceived_exertion,
          location_city, location_state, location_country,
          map_polyline, map_summary_polyline,
          splits_metric, splits_standard, laps, segment_efforts, best_efforts,
          raw_json, details_fetched, updated_at
        ) VALUES (
          ?, ?, ?, ?, ?, ?,
          ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?,
          ?, ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?,
          ?, ?, ?,
          ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?, CURRENT_TIMESTAMP
        )
      SQL
        activity['id'],
        activity.dig('athlete', 'id'),
        activity['name'],
        activity['description'],
        activity['sport_type'],
        activity['type'],
        activity['start_date'],
        activity['start_date_local'],
        activity['timezone'],
        activity['elapsed_time'],
        activity['moving_time'],
        activity['distance'],
        activity['total_elevation_gain'],
        activity['elev_high'],
        activity['elev_low'],
        activity['calories'],
        start_latlng[0],
        start_latlng[1],
        end_latlng[0],
        end_latlng[1],
        activity['average_speed'],
        activity['max_speed'],
        activity['average_heartrate'],
        activity['max_heartrate'],
        activity['suffer_score'],
        activity['average_watts'],
        activity['max_watts'],
        activity['weighted_average_watts'],
        activity['kilojoules'],
        activity['device_watts'] ? 1 : 0,
        activity['average_cadence'],
        activity['average_temp'],
        activity['gear_id'],
        gear_name,
        activity['device_name'],
        activity['trainer'] ? 1 : 0,
        activity['commute'] ? 1 : 0,
        activity['manual'] ? 1 : 0,
        activity['private'] ? 1 : 0,
        activity['flagged'] ? 1 : 0,
        activity['pr_count'],
        activity['achievement_count'],
        activity['kudos_count'],
        activity['comment_count'],
        activity['total_photo_count'] || activity['photo_count'],
        activity['workout_type'],
        activity['perceived_exertion'],
        activity['location_city'],
        activity['location_state'],
        activity['location_country'],
        map_polyline,
        map_summary_polyline,
        splits_metric,
        splits_standard,
        laps,
        segment_efforts,
        best_efforts,
        JSON.generate(activity),
        details_fetched ? 1 : 0
      ])
    end

    def get_all_activities
      @db.execute('SELECT * FROM activities ORDER BY start_date DESC')
    end

    def get_activities_by_sport(sport_type)
      @db.execute('SELECT * FROM activities WHERE sport_type = ? ORDER BY start_date DESC', [sport_type])
    end

    def get_activity_count
      @db.get_first_value('SELECT COUNT(*) FROM activities')
    end

    def get_newest_activity_date
      @db.get_first_value('SELECT MAX(start_date) FROM activities')
    end

    def get_activities_without_details
      @db.execute('SELECT * FROM activities WHERE details_fetched = 0 ORDER BY start_date DESC')
    end

    def get_activities_without_details_count
      @db.get_first_value('SELECT COUNT(*) FROM activities WHERE details_fetched = 0')
    end

    # Resort management
    def upsert_resort(resort)
      @db.execute(<<~SQL, [
        INSERT OR REPLACE INTO resorts (id, name, country, region, latitude, longitude, radius_km, resort_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
        resort[:id],
        resort[:name],
        resort[:country],
        resort[:region],
        resort[:latitude],
        resort[:longitude],
        resort[:radius_km] || 5.0,
        resort[:resort_type] || 'resort'
      ])
    end

    def insert_resort(resort)
      @db.execute(<<~SQL, [
        INSERT INTO resorts (name, country, region, latitude, longitude, radius_km, resort_type)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
        resort[:name],
        resort[:country],
        resort[:region],
        resort[:latitude],
        resort[:longitude],
        resort[:radius_km] || 5.0,
        resort[:resort_type] || 'resort'
      ])
      @db.last_insert_row_id
    end

    def get_all_resorts
      @db.execute('SELECT * FROM resorts ORDER BY name')
    end

    def get_resort_count
      @db.get_first_value('SELECT COUNT(*) FROM resorts')
    end

    # Activity-Resort matching
    def link_activity_to_resort(activity_id:, resort_id:, distance_km:, matched_by:)
      @db.execute(<<~SQL, [activity_id, resort_id, distance_km, matched_by])
        INSERT OR REPLACE INTO activity_resorts (activity_id, resort_id, distance_km, matched_by)
        VALUES (?, ?, ?, ?)
      SQL
    end

    def get_resort_for_activity(activity_id)
      @db.get_first_row(<<~SQL, [activity_id])
        SELECT r.*, ar.distance_km, ar.matched_by
        FROM activity_resorts ar
        JOIN resorts r ON ar.resort_id = r.id
        WHERE ar.activity_id = ?
      SQL
    end

    def get_activities_for_resort(resort_id)
      @db.execute(<<~SQL, [resort_id])
        SELECT a.*, ar.distance_km
        FROM activity_resorts ar
        JOIN activities a ON ar.activity_id = a.id
        WHERE ar.resort_id = ?
        ORDER BY a.start_date DESC
      SQL
    end

    def clear_activity_resorts
      @db.execute('DELETE FROM activity_resorts')
    end

    # Peak management
    def insert_peak(peak)
      elevation_feet = peak[:elevation_meters] ? (peak[:elevation_meters] * 3.28084).round(0) : peak[:elevation_feet]
      elevation_meters = peak[:elevation_feet] ? (peak[:elevation_feet] / 3.28084).round(0) : peak[:elevation_meters]

      @db.execute(<<~SQL, [
        INSERT INTO peaks (name, country, region, latitude, longitude, elevation_meters, elevation_feet, radius_km)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
        peak[:name],
        peak[:country],
        peak[:region],
        peak[:latitude],
        peak[:longitude],
        elevation_meters,
        elevation_feet,
        peak[:radius_km] || 2.0
      ])
      @db.last_insert_row_id
    end

    def get_all_peaks
      @db.execute('SELECT * FROM peaks ORDER BY name')
    end

    def get_peak_count
      @db.get_first_value('SELECT COUNT(*) FROM peaks')
    end

    # Activity-Peak matching
    def link_activity_to_peak(activity_id:, peak_id:, distance_km:)
      @db.execute(<<~SQL, [activity_id, peak_id, distance_km])
        INSERT OR REPLACE INTO activity_peaks (activity_id, peak_id, distance_km)
        VALUES (?, ?, ?)
      SQL
    end

    def get_peak_for_activity(activity_id)
      @db.get_first_row(<<~SQL, [activity_id])
        SELECT p.*, ap.distance_km
        FROM activity_peaks ap
        JOIN peaks p ON ap.peak_id = p.id
        WHERE ap.activity_id = ?
      SQL
    end

    def get_activities_for_peak(peak_id)
      @db.execute(<<~SQL, [peak_id])
        SELECT a.*, ap.distance_km
        FROM activity_peaks ap
        JOIN activities a ON ap.activity_id = a.id
        WHERE ap.peak_id = ?
        ORDER BY a.start_date DESC
      SQL
    end

    def clear_activity_peaks
      @db.execute('DELETE FROM activity_peaks')
    end

    def close
      @db.close
    end
  end
end
