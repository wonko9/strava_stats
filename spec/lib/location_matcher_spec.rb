# frozen_string_literal: true

require 'spec_helper'
require 'location_matcher'

RSpec.describe StravaStats::LocationMatcher do
  let(:database) { instance_double('StravaStats::Database') }
  let(:activities_repo) { instance_double('StravaStats::Repositories::ActivityRepository') }
  let(:resorts_repo) { instance_double('StravaStats::Repositories::ResortRepository') }
  let(:peaks_repo) { instance_double('StravaStats::Repositories::PeakRepository') }
  let(:matcher) { described_class.new(database: database, activities: activities_repo, resorts: resorts_repo, peaks: peaks_repo) }

  before do
    # Suppress logging during tests
    allow(StravaStats).to receive(:logger).and_return(Logger.new(nil))
  end

  describe 'constants' do
    it 'defines Earth radius in km' do
      expect(described_class::EARTH_RADIUS_KM).to eq(6371.0)
    end

    it 'defines default matching radius' do
      expect(described_class::DEFAULT_RADIUS_KM).to eq(5.0)
    end

    it 'defines winter sports' do
      expect(described_class::WINTER_SPORTS).to include('Snowboard', 'AlpineSki', 'BackcountrySki')
    end

    it 'defines backcountry sports' do
      expect(described_class::BACKCOUNTRY_SPORTS).to include('BackcountrySki', 'Snowshoe')
    end
  end

  describe '#find_nearest_resort' do
    let(:resorts) do
      [
        { 'id' => 1, 'name' => 'Vail', 'latitude' => 39.6403, 'longitude' => -106.3742, 'radius_km' => 5.0 },
        { 'id' => 2, 'name' => 'Breckenridge', 'latitude' => 39.4817, 'longitude' => -106.0384, 'radius_km' => 5.0 },
        { 'id' => 3, 'name' => 'Aspen', 'latitude' => 39.1911, 'longitude' => -106.8175, 'radius_km' => 5.0 }
      ]
    end

    it 'finds the nearest resort within radius' do
      # Location very close to Vail
      result = matcher.find_nearest_resort(39.6400, -106.3740, resorts)

      expect(result).not_to be_nil
      expect(result[:resort]['name']).to eq('Vail')
      expect(result[:distance]).to be < 1.0
    end

    it 'returns nil when no resort within radius' do
      # Location far from any resort (Denver)
      result = matcher.find_nearest_resort(39.7392, -104.9903, resorts)

      expect(result).to be_nil
    end

    it 'respects custom radius on resort' do
      small_radius_resort = [
        { 'id' => 1, 'name' => 'Small', 'latitude' => 39.6403, 'longitude' => -106.3742, 'radius_km' => 0.1 }
      ]

      # 1km away - outside 0.1km radius
      result = matcher.find_nearest_resort(39.6493, -106.3742, small_radius_resort)
      expect(result).to be_nil
    end

    it 'uses default radius when resort has none' do
      no_radius_resort = [
        { 'id' => 1, 'name' => 'NoRadius', 'latitude' => 39.6403, 'longitude' => -106.3742 }
      ]

      # Within default 5km radius
      result = matcher.find_nearest_resort(39.6450, -106.3742, no_radius_resort)
      expect(result).not_to be_nil
    end

    it 'returns the closest when multiple resorts in range' do
      close_resorts = [
        { 'id' => 1, 'name' => 'Near', 'latitude' => 39.6403, 'longitude' => -106.3742, 'radius_km' => 10.0 },
        { 'id' => 2, 'name' => 'Far', 'latitude' => 39.6500, 'longitude' => -106.3742, 'radius_km' => 10.0 }
      ]

      result = matcher.find_nearest_resort(39.6403, -106.3742, close_resorts)
      expect(result[:resort]['name']).to eq('Near')
    end

    it 'fetches resorts from repository when not provided' do
      allow(resorts_repo).to receive(:all).and_return(resorts)

      result = matcher.find_nearest_resort(39.6400, -106.3740)
      expect(result[:resort]['name']).to eq('Vail')
    end
  end

  describe '#find_nearest_peak' do
    let(:peaks) do
      [
        { 'id' => 1, 'name' => 'Mt. Elbert', 'latitude' => 39.1178, 'longitude' => -106.4454, 'radius_km' => 2.0 },
        { 'id' => 2, 'name' => 'Mt. Massive', 'latitude' => 39.1875, 'longitude' => -106.4756, 'radius_km' => 2.0 }
      ]
    end

    it 'finds the nearest peak within radius' do
      result = matcher.find_nearest_peak(39.1180, -106.4450, peaks)

      expect(result).not_to be_nil
      expect(result[:peak]['name']).to eq('Mt. Elbert')
    end

    it 'returns nil when no peak within radius' do
      result = matcher.find_nearest_peak(40.0, -105.0, peaks)
      expect(result).to be_nil
    end

    it 'uses default 2km radius when not specified' do
      no_radius_peak = [
        { 'id' => 1, 'name' => 'Test Peak', 'latitude' => 39.0, 'longitude' => -106.0 }
      ]

      # ~1.1km away - within default 2km
      result = matcher.find_nearest_peak(39.01, -106.0, no_radius_peak)
      expect(result).not_to be_nil
    end
  end

  describe 'haversine distance calculation' do
    # Test via find_nearest_resort since haversine_distance is private

    it 'calculates correct distance between known points' do
      # Denver to Boulder is approximately 40km
      denver = [39.7392, -104.9903]
      boulder_resort = [{ 'id' => 1, 'name' => 'Boulder', 'latitude' => 40.0150, 'longitude' => -105.2705, 'radius_km' => 50.0 }]

      result = matcher.find_nearest_resort(denver[0], denver[1], boulder_resort)
      expect(result[:distance]).to be_within(5).of(40)
    end

    it 'returns 0 for same location' do
      same_loc_resort = [{ 'id' => 1, 'name' => 'Here', 'latitude' => 39.0, 'longitude' => -106.0, 'radius_km' => 1.0 }]

      result = matcher.find_nearest_resort(39.0, -106.0, same_loc_resort)
      expect(result[:distance]).to be < 0.001
    end
  end

  describe '#match_all_activities' do
    let(:activities) do
      [
        { 'id' => 1, 'sport_type' => 'Snowboard', 'start_lat' => 39.6403, 'start_lng' => -106.3742 },
        { 'id' => 2, 'sport_type' => 'AlpineSki', 'start_lat' => 39.6403, 'start_lng' => -106.3742 },
        { 'id' => 3, 'sport_type' => 'Run', 'start_lat' => 39.6403, 'start_lng' => -106.3742 },
        { 'id' => 4, 'sport_type' => 'Snowboard', 'start_lat' => nil, 'start_lng' => nil }
      ]
    end

    let(:resorts) do
      [{ 'id' => 1, 'name' => 'Vail', 'latitude' => 39.6403, 'longitude' => -106.3742, 'radius_km' => 5.0 }]
    end

    before do
      allow(activities_repo).to receive(:all).and_return(activities)
      allow(resorts_repo).to receive(:all).and_return(resorts)
      allow(peaks_repo).to receive(:all).and_return([])
      allow(database).to receive(:transaction).and_yield
      allow(resorts_repo).to receive(:clear_activity_links)
      allow(peaks_repo).to receive(:clear_activity_links)
      allow(resorts_repo).to receive(:link_activity)
      allow(peaks_repo).to receive(:link_activity)
    end

    it 'only matches winter sports' do
      matcher.match_all_activities

      expect(resorts_repo).to have_received(:link_activity).exactly(2).times
    end

    it 'skips activities without coordinates' do
      matcher.match_all_activities

      # Activity 4 has no coordinates
      expect(resorts_repo).not_to have_received(:link_activity).with(
        hash_including(activity_id: 4)
      )
    end

    it 'clears existing matches before re-matching' do
      matcher.match_all_activities

      expect(resorts_repo).to have_received(:clear_activity_links).once
    end

    it 'wraps operations in a transaction' do
      matcher.match_all_activities

      expect(database).to have_received(:transaction).once
    end

    it 'returns count of matched activities' do
      result = matcher.match_all_activities
      expect(result).to eq(2)
    end

    it 'also calls match_backcountry_to_peaks' do
      expect(matcher).to receive(:match_backcountry_to_peaks)
      matcher.match_all_activities
    end
  end

  describe '#match_backcountry_to_peaks' do
    let(:activities) do
      [
        { 'id' => 1, 'sport_type' => 'BackcountrySki', 'start_lat' => 39.1178, 'start_lng' => -106.4454 },
        { 'id' => 2, 'sport_type' => 'Snowshoe', 'start_lat' => 39.1178, 'start_lng' => -106.4454 },
        { 'id' => 3, 'sport_type' => 'Snowboard', 'start_lat' => 39.1178, 'start_lng' => -106.4454 },
        { 'id' => 4, 'sport_type' => 'BackcountrySki', 'start_lat' => nil, 'start_lng' => nil }
      ]
    end

    let(:peaks) do
      [{ 'id' => 1, 'name' => 'Mt. Elbert', 'latitude' => 39.1178, 'longitude' => -106.4454, 'radius_km' => 2.0 }]
    end

    before do
      allow(activities_repo).to receive(:all).and_return(activities)
      allow(peaks_repo).to receive(:all).and_return(peaks)
      allow(database).to receive(:transaction).and_yield
      allow(peaks_repo).to receive(:clear_activity_links)
      allow(peaks_repo).to receive(:link_activity)
    end

    it 'only matches backcountry sports' do
      matcher.match_backcountry_to_peaks

      expect(peaks_repo).to have_received(:link_activity).exactly(2).times
    end

    it 'returns 0 when no peaks exist' do
      allow(peaks_repo).to receive(:all).and_return([])

      result = matcher.match_backcountry_to_peaks
      expect(result).to eq(0)
    end

    it 'skips activities without coordinates' do
      matcher.match_backcountry_to_peaks

      expect(peaks_repo).not_to have_received(:link_activity).with(
        hash_including(activity_id: 4)
      )
    end

    it 'wraps operations in a transaction' do
      matcher.match_backcountry_to_peaks

      expect(database).to have_received(:transaction).once
    end
  end

  describe '#seed_resorts_if_empty' do
    context 'when resorts table is empty' do
      before do
        allow(resorts_repo).to receive(:count).and_return(0, 5)
        allow(resorts_repo).to receive(:insert)
        allow(File).to receive(:exist?).and_return(true)
        allow(YAML).to receive(:load_file).and_return([
                                                        { 'name' => 'Test Resort', 'country' => 'USA', 'region' => 'CO', 'latitude' => 39.0, 'longitude' => -106.0 }
                                                      ])
      end

      it 'seeds resorts from YAML file' do
        matcher.seed_resorts_if_empty

        expect(resorts_repo).to have_received(:insert).once
      end
    end

    context 'when resorts already exist' do
      before do
        allow(resorts_repo).to receive(:count).and_return(10)
      end

      it 'does not seed resorts' do
        expect(resorts_repo).not_to receive(:insert)
        matcher.seed_resorts_if_empty
      end
    end
  end

  describe '#seed_peaks_if_empty' do
    context 'when peaks table is empty' do
      before do
        allow(peaks_repo).to receive(:count).and_return(0, 3)
        allow(peaks_repo).to receive(:insert)
        allow(File).to receive(:exist?).and_return(true)
        allow(YAML).to receive(:load_file).and_return([
                                                        { 'name' => 'Test Peak', 'country' => 'USA', 'region' => 'CO', 'latitude' => 39.0, 'longitude' => -106.0, 'elevation_meters' => 4000 }
                                                      ])
      end

      it 'seeds peaks from YAML file' do
        matcher.seed_peaks_if_empty

        expect(peaks_repo).to have_received(:insert).once
      end
    end

    context 'when peaks already exist' do
      before do
        allow(peaks_repo).to receive(:count).and_return(5)
      end

      it 'does not seed peaks' do
        expect(peaks_repo).not_to receive(:insert)
        matcher.seed_peaks_if_empty
      end
    end
  end
end
