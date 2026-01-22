# frozen_string_literal: true

require 'spec_helper'
require 'database'
require 'tempfile'
require 'fileutils'

RSpec.describe StravaStats::Database do
  let(:db_file) { Tempfile.new(['test_db', '.db']) }
  let(:database) { described_class.new(db_file.path) }

  after do
    database.close
    db_file.close
    db_file.unlink
  end

  describe '#initialize' do
    it 'creates the database file' do
      expect(File.exist?(db_file.path)).to be true
    end

    it 'sets up the schema with required tables' do
      # Verify tables exist by querying them
      expect { database.get_all_activities }.not_to raise_error
      expect { database.get_all_resorts }.not_to raise_error
      expect { database.get_all_peaks }.not_to raise_error
      expect { database.get_tokens }.not_to raise_error
    end
  end

  describe 'token management' do
    describe '#save_tokens and #get_tokens' do
      it 'saves and retrieves tokens' do
        database.save_tokens(
          access_token: 'access123',
          refresh_token: 'refresh456',
          expires_at: 1234567890
        )

        tokens = database.get_tokens
        expect(tokens[:access_token]).to eq('access123')
        expect(tokens[:refresh_token]).to eq('refresh456')
        expect(tokens[:expires_at]).to eq(1234567890)
      end

      it 'saves athlete data as JSON' do
        athlete = { 'firstname' => 'John', 'lastname' => 'Doe', 'id' => 12345 }
        database.save_tokens(
          access_token: 'access123',
          refresh_token: 'refresh456',
          expires_at: 1234567890,
          athlete: athlete
        )

        tokens = database.get_tokens
        expect(tokens[:athlete]).to eq(athlete)
      end

      it 'returns nil when no tokens exist' do
        expect(database.get_tokens).to be_nil
      end

      it 'overwrites existing tokens' do
        database.save_tokens(access_token: 'old', refresh_token: 'old', expires_at: 1)
        database.save_tokens(access_token: 'new', refresh_token: 'new', expires_at: 2)

        tokens = database.get_tokens
        expect(tokens[:access_token]).to eq('new')
      end
    end
  end

  describe 'sync state management' do
    describe '#get_last_sync_at and #set_last_sync_at' do
      it 'returns nil initially' do
        expect(database.get_last_sync_at).to be_nil
      end

      it 'saves and retrieves sync timestamp' do
        timestamp = Time.now.to_i
        database.set_last_sync_at(timestamp)
        expect(database.get_last_sync_at).to eq(timestamp)
      end

      it 'updates existing timestamp' do
        database.set_last_sync_at(1000)
        database.set_last_sync_at(2000)
        expect(database.get_last_sync_at).to eq(2000)
      end
    end
  end

  describe 'activity management' do
    let(:activity) do
      {
        'id' => 12345,
        'athlete' => { 'id' => 999 },
        'name' => 'Morning Run',
        'sport_type' => 'Run',
        'type' => 'Run',
        'start_date' => '2024-01-15T08:00:00Z',
        'start_date_local' => '2024-01-15T08:00:00Z',
        'distance' => 5000.0,
        'moving_time' => 1800,
        'total_elevation_gain' => 50.0,
        'calories' => 300,
        'start_latlng' => [39.7392, -104.9903],
        'end_latlng' => [39.7400, -104.9900]
      }
    end

    describe '#upsert_activity' do
      it 'inserts a new activity' do
        database.upsert_activity(activity)
        expect(database.get_activity_count).to eq(1)
      end

      it 'updates existing activity' do
        database.upsert_activity(activity)
        updated = activity.merge('name' => 'Updated Run')
        database.upsert_activity(updated)

        result = database.get_activity(12345)
        expect(result['name']).to eq('Updated Run')
        expect(database.get_activity_count).to eq(1)
      end

      it 'extracts start/end coordinates from arrays' do
        database.upsert_activity(activity)
        result = database.get_activity(12345)

        expect(result['start_lat']).to eq(39.7392)
        expect(result['start_lng']).to eq(-104.9903)
        expect(result['end_lat']).to eq(39.7400)
        expect(result['end_lng']).to eq(-104.9900)
      end

      it 'handles missing optional fields' do
        minimal = { 'id' => 1, 'athlete' => { 'id' => 1 } }
        expect { database.upsert_activity(minimal) }.not_to raise_error
      end

      it 'sets details_fetched flag' do
        database.upsert_activity(activity, details_fetched: true)
        result = database.get_activity(12345)
        expect(result['details_fetched']).to eq(1)
      end
    end

    describe '#get_all_activities' do
      before do
        database.upsert_activity(activity)
        database.upsert_activity(activity.merge('id' => 2, 'name' => 'Second'))
      end

      it 'returns all activities' do
        expect(database.get_all_activities.count).to eq(2)
      end

      it 'excludes ignored activities by default' do
        database.ignore_activity(12345)
        expect(database.get_all_activities.count).to eq(1)
      end

      it 'includes ignored activities when requested' do
        database.ignore_activity(12345)
        expect(database.get_all_activities(include_ignored: true).count).to eq(2)
      end

      it 'orders by start_date descending' do
        database.upsert_activity(activity.merge('id' => 3, 'start_date' => '2024-01-20T00:00:00Z'))
        results = database.get_all_activities
        expect(results.first['id']).to eq(3)
      end
    end

    describe '#get_activities_by_sport' do
      before do
        database.upsert_activity(activity)
        database.upsert_activity(activity.merge('id' => 2, 'sport_type' => 'Ride'))
      end

      it 'filters by sport type' do
        runs = database.get_activities_by_sport('Run')
        expect(runs.count).to eq(1)
        expect(runs.first['sport_type']).to eq('Run')
      end
    end

    describe '#ignore_activity and #unignore_activity' do
      before { database.upsert_activity(activity) }

      it 'marks activity as ignored' do
        database.ignore_activity(12345)
        expect(database.get_ignored_activities.count).to eq(1)
      end

      it 'restores ignored activity' do
        database.ignore_activity(12345)
        database.unignore_activity(12345)
        expect(database.get_ignored_activities.count).to eq(0)
      end
    end

    describe '#get_activities_without_details' do
      it 'returns activities without details_fetched' do
        database.upsert_activity(activity, details_fetched: false)
        database.upsert_activity(activity.merge('id' => 2), details_fetched: true)

        without_details = database.get_activities_without_details
        expect(without_details.count).to eq(1)
        expect(without_details.first['id']).to eq(12345)
      end
    end

    describe '#get_newest_activity_date' do
      it 'returns the most recent activity date' do
        database.upsert_activity(activity.merge('start_date' => '2024-01-10T00:00:00Z'))
        database.upsert_activity(activity.merge('id' => 2, 'start_date' => '2024-01-20T00:00:00Z'))

        expect(database.get_newest_activity_date).to eq('2024-01-20T00:00:00Z')
      end

      it 'returns nil when no activities' do
        expect(database.get_newest_activity_date).to be_nil
      end
    end
  end

  describe 'resort management' do
    let(:resort) do
      {
        name: 'Vail',
        country: 'USA',
        region: 'Colorado',
        latitude: 39.6403,
        longitude: -106.3742,
        radius_km: 5.0,
        resort_type: 'resort'
      }
    end

    describe '#insert_resort' do
      it 'inserts a resort and returns its ID' do
        id = database.insert_resort(resort)
        expect(id).to be > 0
        expect(database.get_resort_count).to eq(1)
      end

      it 'uses default radius when not specified' do
        id = database.insert_resort(resort.except(:radius_km))
        resorts = database.get_all_resorts
        expect(resorts.first['radius_km']).to eq(5.0)
      end
    end

    describe '#get_all_resorts' do
      it 'returns resorts ordered by name' do
        database.insert_resort(resort.merge(name: 'Zermatt'))
        database.insert_resort(resort.merge(name: 'Aspen'))

        resorts = database.get_all_resorts
        expect(resorts.map { |r| r['name'] }).to eq(%w[Aspen Zermatt])
      end
    end
  end

  describe 'peak management' do
    let(:peak) do
      {
        name: 'Mt. Elbert',
        country: 'USA',
        region: 'Colorado',
        latitude: 39.1178,
        longitude: -106.4454,
        elevation_meters: 4401,
        radius_km: 2.0
      }
    end

    describe '#insert_peak' do
      it 'inserts a peak and calculates elevation in feet' do
        database.insert_peak(peak)
        peaks = database.get_all_peaks
        expect(peaks.first['elevation_feet']).to be_within(1).of(14439)
      end

      it 'handles elevation_feet input' do
        database.insert_peak(peak.merge(elevation_meters: nil, elevation_feet: 14439))
        peaks = database.get_all_peaks
        expect(peaks.first['elevation_meters']).to be_within(1).of(4401)
      end
    end
  end

  describe 'activity-resort linking' do
    let(:activity) { { 'id' => 1, 'athlete' => { 'id' => 1 }, 'sport_type' => 'Snowboard' } }
    let(:resort) { { name: 'Vail', country: 'USA', region: 'CO', latitude: 39.64, longitude: -106.37 } }

    before do
      database.upsert_activity(activity)
      @resort_id = database.insert_resort(resort)
    end

    describe '#link_activity_to_resort' do
      it 'creates a link between activity and resort' do
        database.link_activity_to_resort(
          activity_id: 1,
          resort_id: @resort_id,
          distance_km: 1.5,
          matched_by: 'gps'
        )

        result = database.get_resort_for_activity(1)
        expect(result['name']).to eq('Vail')
        expect(result['distance_km']).to eq(1.5)
      end
    end

    describe '#get_activities_for_resort' do
      it 'returns activities linked to a resort' do
        database.link_activity_to_resort(activity_id: 1, resort_id: @resort_id, distance_km: 1.0, matched_by: 'gps')

        activities = database.get_activities_for_resort(@resort_id)
        expect(activities.count).to eq(1)
        expect(activities.first['id']).to eq(1)
      end
    end

    describe '#clear_activity_resorts' do
      it 'removes all activity-resort links' do
        database.link_activity_to_resort(activity_id: 1, resort_id: @resort_id, distance_km: 1.0, matched_by: 'gps')
        database.clear_activity_resorts
        expect(database.get_resort_for_activity(1)).to be_nil
      end
    end
  end

  describe 'batch query methods' do
    let(:activities) do
      [
        { 'id' => 1, 'athlete' => { 'id' => 1 }, 'sport_type' => 'Snowboard' },
        { 'id' => 2, 'athlete' => { 'id' => 1 }, 'sport_type' => 'AlpineSki' },
        { 'id' => 3, 'athlete' => { 'id' => 1 }, 'sport_type' => 'BackcountrySki' }
      ]
    end

    before do
      activities.each { |a| database.upsert_activity(a) }
      @resort_id = database.insert_resort(name: 'Vail', country: 'USA', region: 'CO', latitude: 39.64, longitude: -106.37)
      @peak_id = database.insert_peak(name: 'Mt. Elbert', country: 'USA', region: 'CO', latitude: 39.11, longitude: -106.44, elevation_meters: 4401)
    end

    describe '#get_resorts_for_activities' do
      it 'returns empty hash for empty input' do
        expect(database.get_resorts_for_activities([])).to eq({})
      end

      it 'returns hash of activity_id to resort' do
        database.link_activity_to_resort(activity_id: 1, resort_id: @resort_id, distance_km: 1.0, matched_by: 'gps')
        database.link_activity_to_resort(activity_id: 2, resort_id: @resort_id, distance_km: 2.0, matched_by: 'gps')

        result = database.get_resorts_for_activities([1, 2, 3])
        expect(result.keys).to contain_exactly(1, 2)
        expect(result[1]['name']).to eq('Vail')
        expect(result[2]['distance_km']).to eq(2.0)
      end
    end

    describe '#get_peaks_for_activities' do
      it 'returns empty hash for empty input' do
        expect(database.get_peaks_for_activities([])).to eq({})
      end

      it 'returns hash of activity_id to peak' do
        database.link_activity_to_peak(activity_id: 3, peak_id: @peak_id, distance_km: 0.5)

        result = database.get_peaks_for_activities([1, 2, 3])
        expect(result.keys).to contain_exactly(3)
        expect(result[3]['name']).to eq('Mt. Elbert')
      end
    end
  end

  describe '#transaction' do
    it 'commits on success' do
      database.transaction do
        database.upsert_activity({ 'id' => 1, 'athlete' => { 'id' => 1 } })
      end
      expect(database.get_activity_count).to eq(1)
    end

    it 'rolls back on error' do
      expect do
        database.transaction do
          database.upsert_activity({ 'id' => 1, 'athlete' => { 'id' => 1 } })
          raise 'Simulated error'
        end
      end.to raise_error('Simulated error')

      expect(database.get_activity_count).to eq(0)
    end
  end
end
