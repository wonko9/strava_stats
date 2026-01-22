# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StravaStats::StatsCalculator do
  let(:database) do
    instance_double('StravaStats::Database',
                    get_all_activities: [],
                    get_resort_for_activity: nil,
                    get_peak_for_activity: nil)
  end
  let(:calculator) { described_class.new(database: database) }

  describe 'constants' do
    it 'defines correct unit conversions' do
      expect(described_class::METERS_TO_MILES).to be_within(0.0000001).of(0.000621371)
      expect(described_class::METERS_TO_FEET).to be_within(0.00001).of(3.28084)
      expect(described_class::SECONDS_TO_HOURS).to be_within(0.0000001).of(1.0 / 3600)
    end

    it 'defines winter sports list' do
      expect(described_class::WINTER_SPORTS).to contain_exactly(
        'Snowboard', 'AlpineSki', 'BackcountrySki', 'NordicSki', 'Snowshoe'
      )
    end
  end

  describe '#calculate_summary' do
    context 'with empty activities' do
      it 'returns zero totals' do
        result = calculator.calculate_summary([])

        expect(result[:total_activities]).to eq(0)
        expect(result[:total_sports]).to eq(0)
        expect(result[:total_distance_miles]).to eq(0.0)
        expect(result[:total_elevation_feet]).to eq(0)
        expect(result[:total_time_hours]).to eq(0.0)
        expect(result[:total_calories]).to eq(0)
        expect(result[:date_range]).to be_nil
      end
    end

    context 'with single activity' do
      let(:activity) { TestFixtures.run_activity }

      it 'calculates correct totals' do
        result = calculator.calculate_summary([activity])

        expect(result[:total_activities]).to eq(1)
        expect(result[:total_sports]).to eq(1)
        # 8000m * 0.000621371 = 4.97
        expect(result[:total_distance_miles]).to be_within(0.1).of(5.0)
        # 150m * 3.28084 = 492
        expect(result[:total_elevation_feet]).to be_within(5).of(492)
        # 2400s / 3600 = 0.67
        expect(result[:total_time_hours]).to be_within(0.1).of(0.7)
        expect(result[:total_calories]).to eq(500)
      end

      it 'returns correct date range' do
        result = calculator.calculate_summary([activity])

        expect(result[:date_range][:first]).to eq('2024-06-15T08:00:00Z')
        expect(result[:date_range][:last]).to eq('2024-06-15T08:00:00Z')
      end
    end

    context 'with multiple activities and sports' do
      let(:activities) { TestFixtures.mixed_activities_2024 }

      it 'calculates correct totals' do
        result = calculator.calculate_summary(activities)

        expect(result[:total_activities]).to eq(7)
        expect(result[:total_sports]).to eq(4) # Run, Ride, Snowboard, AlpineSki
      end

      it 'returns correct date range spanning multiple dates' do
        result = calculator.calculate_summary(activities)

        expect(result[:date_range][:first]).to eq('2024-01-15T10:00:00Z')
        expect(result[:date_range][:last]).to eq('2024-07-15T08:00:00Z')
      end
    end

    context 'with activity missing optional fields' do
      let(:activity) { TestFixtures.activity_with_missing_fields }

      it 'handles missing fields gracefully with defaults' do
        result = calculator.calculate_summary([activity])

        expect(result[:total_activities]).to eq(1)
        expect(result[:total_distance_miles]).to eq(0.0)
        expect(result[:total_elevation_feet]).to eq(0)
        expect(result[:total_time_hours]).to eq(0.0)
        expect(result[:total_calories]).to eq(0)
      end
    end
  end

  describe '#calculate_by_sport' do
    context 'with empty activities' do
      it 'returns empty hash' do
        expect(calculator.calculate_by_sport([])).to eq({})
      end
    end

    context 'with multiple sports' do
      let(:activities) do
        [
          TestFixtures.run_activity(date: '2024-06-15T08:00:00Z'),
          TestFixtures.run_activity(date: '2024-06-16T08:00:00Z'),
          TestFixtures.run_activity(date: '2024-06-17T08:00:00Z'),
          TestFixtures.ride_activity(date: '2024-06-18T09:00:00Z')
        ]
      end

      it 'groups activities by sport' do
        result = calculator.calculate_by_sport(activities)

        expect(result.keys).to contain_exactly('Run', 'Ride')
        expect(result['Run'][:total_activities]).to eq(3)
        expect(result['Ride'][:total_activities]).to eq(1)
      end

      it 'sorts by activity count descending' do
        result = calculator.calculate_by_sport(activities)

        expect(result.keys.first).to eq('Run')
        expect(result.keys.last).to eq('Ride')
      end

      it 'includes activity summaries' do
        result = calculator.calculate_by_sport(activities)

        expect(result['Run'][:activities]).to be_an(Array)
        expect(result['Run'][:activities].length).to eq(3)
        expect(result['Run'][:activities].first).to have_key(:id)
        expect(result['Run'][:activities].first).to have_key(:name)
      end

      it 'counts unique days correctly' do
        result = calculator.calculate_by_sport(activities)

        expect(result['Run'][:total_days]).to eq(3)
        expect(result['Ride'][:total_days]).to eq(1)
      end
    end
  end

  describe '#calculate_by_year' do
    context 'with empty activities' do
      it 'returns empty hash' do
        expect(calculator.calculate_by_year([])).to eq({})
      end
    end

    context 'with activities across multiple years' do
      let(:activities) { TestFixtures.activities_multiple_years }

      it 'groups activities by year' do
        result = calculator.calculate_by_year(activities)

        expect(result.keys).to contain_exactly(2022, 2023, 2024)
        expect(result[2022][:total_activities]).to eq(2)
        expect(result[2023][:total_activities]).to eq(2)
        expect(result[2024][:total_activities]).to eq(3)
      end

      it 'sorts by year ascending' do
        result = calculator.calculate_by_year(activities)

        expect(result.keys).to eq([2022, 2023, 2024])
      end
    end
  end

  describe '#calculate_by_sport_and_year' do
    context 'with empty activities' do
      it 'returns empty hash' do
        expect(calculator.calculate_by_sport_and_year([])).to eq({})
      end
    end

    context 'with activities across sports and years' do
      let(:activities) { TestFixtures.activities_multiple_years }

      it 'creates nested hash of sport -> year -> stats' do
        result = calculator.calculate_by_sport_and_year(activities)

        expect(result).to have_key('Run')
        expect(result).to have_key('Ride')
        expect(result['Run']).to have_key(2022)
        expect(result['Run']).to have_key(2024)
        expect(result['Ride']).to have_key(2023)
        expect(result['Ride']).to have_key(2024)
      end

      it 'calculates correct stats for each combination' do
        result = calculator.calculate_by_sport_and_year(activities)

        expect(result['Run'][2022][:total_activities]).to eq(2)
        expect(result['Run'][2024][:total_activities]).to eq(2)
        expect(result['Ride'][2024][:total_activities]).to eq(1)
      end

      it 'sorts sports alphabetically' do
        result = calculator.calculate_by_sport_and_year(activities)

        expect(result.keys).to eq(result.keys.sort)
      end

      it 'sorts years ascending within each sport' do
        result = calculator.calculate_by_sport_and_year(activities)

        result.each_value do |years|
          expect(years.keys).to eq(years.keys.sort)
        end
      end
    end
  end

  describe '#calculate_winter_by_season' do
    context 'with empty activities' do
      it 'returns empty hash' do
        expect(calculator.calculate_winter_by_season([])).to eq({})
      end
    end

    context 'with non-winter activities only' do
      let(:activities) do
        [
          TestFixtures.run_activity,
          TestFixtures.ride_activity
        ]
      end

      it 'returns empty hash' do
        expect(calculator.calculate_winter_by_season(activities)).to eq({})
      end
    end

    context 'with winter activities across seasons' do
      let(:activities) { TestFixtures.winter_activities_multiple_seasons }

      it 'groups by winter season' do
        result = calculator.calculate_winter_by_season(activities)

        expect(result.keys).to contain_exactly('2023-24', '2024-25')
      end

      it 'includes totals for each season' do
        result = calculator.calculate_winter_by_season(activities)

        expect(result['2023-24'][:totals][:total_activities]).to eq(4)
        expect(result['2024-25'][:totals][:total_activities]).to eq(3)
      end

      it 'includes breakdown by sport' do
        result = calculator.calculate_winter_by_season(activities)

        expect(result['2023-24'][:by_sport]).to have_key('Snowboard')
        expect(result['2023-24'][:by_sport]).to have_key('AlpineSki')
        expect(result['2023-24'][:by_sport]).to have_key('BackcountrySki')
        expect(result['2023-24'][:by_sport]['Snowboard'][:total_activities]).to eq(2)
      end

      it 'sorts by season ascending' do
        result = calculator.calculate_winter_by_season(activities)

        expect(result.keys).to eq(['2023-24', '2024-25'])
      end
    end

    context 'with season boundary dates' do
      it 'assigns September activity to new season' do
        activity = TestFixtures.snowboard_activity(date: '2024-09-15T10:00:00Z')
        result = calculator.calculate_winter_by_season([activity])

        expect(result.keys).to eq(['2024-25'])
      end

      it 'assigns August activity to previous season' do
        activity = TestFixtures.snowboard_activity(date: '2024-08-15T10:00:00Z')
        result = calculator.calculate_winter_by_season([activity])

        expect(result.keys).to eq(['2023-24'])
      end

      it 'assigns January activity to season that started previous September' do
        activity = TestFixtures.snowboard_activity(date: '2024-01-15T10:00:00Z')
        result = calculator.calculate_winter_by_season([activity])

        expect(result.keys).to eq(['2023-24'])
      end
    end
  end

  describe '#calculate_resorts_by_season' do
    context 'with activities matched to resorts' do
      let(:activities) do
        [
          TestFixtures.snowboard_activity(date: '2024-01-15T10:00:00Z', 'id' => 1001),
          TestFixtures.alpine_ski_activity(date: '2024-01-20T09:00:00Z', 'id' => 1002)
        ]
      end
      let(:resort) { TestFixtures.mock_resort(name: 'Vail') }

      before do
        allow(database).to receive(:get_resort_for_activity).and_return(resort)
      end

      it 'groups activities by resort within season' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result).to have_key('2023-24')
        expect(result['2023-24']).to have_key('Vail')
        expect(result['2023-24']['Vail'][:activities].length).to eq(2)
      end

      it 'includes resort info' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result['2023-24']['Vail'][:resort]).to eq(resort)
      end

      it 'calculates stats for each resort' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result['2023-24']['Vail'][:stats][:total_activities]).to eq(2)
      end
    end

    context 'with backcountry resort type' do
      let(:activities) do
        [TestFixtures.snowboard_activity(date: '2024-01-15T10:00:00Z', 'id' => 1001)]
      end
      let(:backcountry_resort) { TestFixtures.mock_resort(name: 'BC Zone', resort_type: 'backcountry') }

      before do
        allow(database).to receive(:get_resort_for_activity).and_return(backcountry_resort)
      end

      it 'excludes backcountry resorts' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result).to eq({})
      end
    end

    context 'with no resort match' do
      let(:activities) do
        [TestFixtures.snowboard_activity(date: '2024-01-15T10:00:00Z', 'id' => 1001)]
      end

      before do
        allow(database).to receive(:get_resort_for_activity).and_return(nil)
      end

      it 'skips activities without resort match' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result).to eq({})
      end
    end

    context 'with non-ski activities' do
      let(:activities) do
        [TestFixtures.run_activity(date: '2024-01-15T08:00:00Z')]
      end

      it 'skips non-ski activities' do
        result = calculator.calculate_resorts_by_season(activities)

        expect(result).to eq({})
      end
    end
  end

  describe '#calculate_backcountry_by_season' do
    context 'with backcountry ski activities' do
      let(:activities) do
        [
          TestFixtures.backcountry_ski_activity(date: '2024-02-10T07:00:00Z', 'id' => 1001),
          TestFixtures.backcountry_ski_activity(date: '2024-02-15T07:00:00Z', 'id' => 1002)
        ]
      end

      context 'with backcountry resort match' do
        let(:bc_resort) { TestFixtures.mock_resort(name: 'Berthoud Pass', resort_type: 'backcountry') }

        before do
          allow(database).to receive(:get_resort_for_activity).and_return(bc_resort)
        end

        it 'uses resort name for region' do
          result = calculator.calculate_backcountry_by_season(activities)

          expect(result['2023-24']).to have_key('Berthoud Pass')
        end
      end

      context 'with regular resort match' do
        let(:resort) { TestFixtures.mock_resort(name: 'Vail', resort_type: 'resort') }

        before do
          allow(database).to receive(:get_resort_for_activity).and_return(resort)
        end

        it 'appends "area" to resort name' do
          result = calculator.calculate_backcountry_by_season(activities)

          expect(result['2023-24']).to have_key('Vail area')
        end
      end

      context 'with no resort match' do
        before do
          allow(database).to receive(:get_resort_for_activity).and_return(nil)
        end

        it 'falls back to location_state' do
          result = calculator.calculate_backcountry_by_season(activities)

          expect(result['2023-24']).to have_key('Colorado')
        end

        it 'falls back to location_country when state missing' do
          activities.each { |a| a.delete('location_state') }
          result = calculator.calculate_backcountry_by_season(activities)

          expect(result['2023-24']).to have_key('USA')
        end

        it 'uses Unknown when no location data' do
          activities.each do |a|
            a.delete('location_state')
            a.delete('location_country')
          end
          result = calculator.calculate_backcountry_by_season(activities)

          expect(result['2023-24']).to have_key('Unknown')
        end
      end
    end
  end

  describe '#calculate_peaks_by_season' do
    context 'with backcountry activities matched to peaks' do
      let(:activities) do
        [
          TestFixtures.backcountry_ski_activity(date: '2024-02-10T07:00:00Z', 'id' => 1001),
          TestFixtures.backcountry_ski_activity(date: '2024-02-15T07:00:00Z', 'id' => 1002)
        ]
      end
      let(:peak) { TestFixtures.mock_peak(name: 'Mt. Elbert') }

      before do
        allow(database).to receive(:get_peak_for_activity).and_return(peak)
      end

      it 'groups activities by peak' do
        result = calculator.calculate_peaks_by_season(activities)

        expect(result['2023-24']).to have_key('Mt. Elbert')
        expect(result['2023-24']['Mt. Elbert'][:activities].length).to eq(2)
      end

      it 'includes peak info' do
        result = calculator.calculate_peaks_by_season(activities)

        expect(result['2023-24']['Mt. Elbert'][:peak]).to eq(peak)
      end
    end

    context 'with no peak match' do
      let(:activities) do
        [TestFixtures.backcountry_ski_activity(date: '2024-02-10T07:00:00Z', 'id' => 1001)]
      end

      before do
        allow(database).to receive(:get_peak_for_activity).and_return(nil)
      end

      it 'skips activities without peak match' do
        result = calculator.calculate_peaks_by_season(activities)

        expect(result).to eq({})
      end
    end

    context 'with non-backcountry activities' do
      let(:activities) do
        [TestFixtures.snowboard_activity(date: '2024-01-15T10:00:00Z', 'id' => 1001)]
      end

      it 'skips non-backcountry activities' do
        result = calculator.calculate_peaks_by_season(activities)

        expect(result).to eq({})
      end
    end
  end

  describe '#calculate_year_comparisons' do
    let(:activities) { TestFixtures.activities_multiple_years }
    let(:by_sport_and_year) { calculator.calculate_by_sport_and_year(activities) }

    before do
      allow(database).to receive(:get_all_activities).and_return(activities)
      allow(Time).to receive(:now).and_return(Time.new(2024, 6, 15, 12, 0, 0))
    end

    it 'returns comparison data for each sport' do
      result = calculator.calculate_year_comparisons(by_sport_and_year)

      expect(result).to have_key('Run')
      expect(result).to have_key('Ride')
    end

    it 'includes available years' do
      result = calculator.calculate_year_comparisons(by_sport_and_year)

      expect(result['Run'][:available_years]).to include(2022, 2024)
    end

    it 'includes current year info' do
      result = calculator.calculate_year_comparisons(by_sport_and_year)

      expect(result['Run'][:current_year]).to eq(2024)
      expect(result['Run'][:current_day]).to eq(167) # June 15 = day 167
    end

    it 'includes cumulative data for each year' do
      result = calculator.calculate_year_comparisons(by_sport_and_year)

      expect(result['Run'][:yearly_data]).to have_key(2022)
      expect(result['Run'][:yearly_data]).to have_key(2024)
      expect(result['Run'][:yearly_data][2024]).to have_key(:cumulative)
    end

    it 'calculates cumulative stats correctly' do
      result = calculator.calculate_year_comparisons(by_sport_and_year)

      cumulative = result['Run'][:yearly_data][2024][:cumulative]
      expect(cumulative).to be_an(Array)
      expect(cumulative.last[:activities]).to eq(2) # 2 run activities in 2024
    end
  end

  describe '#calculate_season_comparisons' do
    let(:activities) { TestFixtures.winter_activities_multiple_seasons }
    let(:winter_by_season) { calculator.calculate_winter_by_season(activities) }

    before do
      allow(database).to receive(:get_all_activities).and_return(activities)
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 15, 12, 0, 0))
    end

    it 'returns comparison data for each winter sport' do
      result = calculator.calculate_season_comparisons(winter_by_season)

      expect(result).to have_key('Snowboard')
      expect(result).to have_key('AlpineSki')
    end

    it 'includes available seasons' do
      result = calculator.calculate_season_comparisons(winter_by_season)

      expect(result['Snowboard'][:available_seasons]).to include('2023-24', '2024-25')
    end

    it 'includes current season info' do
      result = calculator.calculate_season_comparisons(winter_by_season)

      expect(result['Snowboard'][:current_season]).to eq('2024-25')
    end

    it 'calculates day of season correctly' do
      result = calculator.calculate_season_comparisons(winter_by_season)

      # Jan 15 is about 136 days from Sep 1
      expect(result['Snowboard'][:current_day]).to be_within(2).of(136)
    end

    it 'includes cumulative data for each season' do
      result = calculator.calculate_season_comparisons(winter_by_season)

      expect(result['Snowboard'][:season_data]).to have_key('2023-24')
      expect(result['Snowboard'][:season_data]).to have_key('2024-25')
      expect(result['Snowboard'][:season_data]['2024-25']).to have_key(:cumulative)
    end
  end

  describe '#calculate_all_stats' do
    let(:activities) { TestFixtures.mixed_activities_2024 }

    before do
      allow(database).to receive(:get_all_activities).and_return(activities)
      allow(Time).to receive(:now).and_return(Time.new(2024, 6, 15, 12, 0, 0))
    end

    it 'returns all stat categories' do
      result = calculator.calculate_all_stats

      expect(result).to have_key(:summary)
      expect(result).to have_key(:by_sport)
      expect(result).to have_key(:by_year)
      expect(result).to have_key(:by_sport_and_year)
      expect(result).to have_key(:winter_by_season)
      expect(result).to have_key(:resorts_by_season)
      expect(result).to have_key(:backcountry_by_season)
      expect(result).to have_key(:peaks_by_season)
      expect(result).to have_key(:year_comparisons)
      expect(result).to have_key(:season_comparisons)
    end
  end

  describe 'private helper methods' do
    describe 'extract_winter_season' do
      it 'assigns Sep-Dec to current year season' do
        calculator = described_class.new(database: database)

        # Use send to test private method
        expect(calculator.send(:extract_winter_season, '2024-09-15T10:00:00Z')).to eq('2024-25')
        expect(calculator.send(:extract_winter_season, '2024-10-01T10:00:00Z')).to eq('2024-25')
        expect(calculator.send(:extract_winter_season, '2024-11-15T10:00:00Z')).to eq('2024-25')
        expect(calculator.send(:extract_winter_season, '2024-12-31T10:00:00Z')).to eq('2024-25')
      end

      it 'assigns Jan-Aug to previous year season' do
        calculator = described_class.new(database: database)

        expect(calculator.send(:extract_winter_season, '2024-01-01T10:00:00Z')).to eq('2023-24')
        expect(calculator.send(:extract_winter_season, '2024-02-15T10:00:00Z')).to eq('2023-24')
        expect(calculator.send(:extract_winter_season, '2024-08-31T10:00:00Z')).to eq('2023-24')
      end

      it 'handles year 2000 correctly' do
        calculator = described_class.new(database: database)

        expect(calculator.send(:extract_winter_season, '2000-01-15T10:00:00Z')).to eq('1999-0')
        expect(calculator.send(:extract_winter_season, '1999-12-15T10:00:00Z')).to eq('1999-0')
      end

      it 'returns nil for nil input' do
        calculator = described_class.new(database: database)

        expect(calculator.send(:extract_winter_season, nil)).to be_nil
      end
    end

    describe 'unit conversion helpers' do
      let(:activities) do
        [TestFixtures.base_activity(
          'distance' => 10000.0,
          'total_elevation_gain' => 1000.0,
          'moving_time' => 3600,
          'calories' => 500.5
        )]
      end

      it 'converts meters to miles correctly' do
        result = calculator.send(:sum_distance_miles, activities)

        # 10000m * 0.000621371 = 6.21371
        expect(result).to be_within(0.1).of(6.2)
      end

      it 'converts meters to feet correctly' do
        result = calculator.send(:sum_elevation_feet, activities)

        # 1000m * 3.28084 = 3280.84
        expect(result).to be_within(5).of(3281)
      end

      it 'converts seconds to hours correctly' do
        result = calculator.send(:sum_time_hours, activities)

        # 3600s / 3600 = 1.0
        expect(result).to eq(1.0)
      end

      it 'rounds calories to integer' do
        result = calculator.send(:sum_calories, activities)

        expect(result).to eq(501)
      end
    end
  end
end
