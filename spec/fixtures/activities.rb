# frozen_string_literal: true

module TestFixtures
  module_function

  def base_activity(overrides = {})
    {
      'id' => rand(1_000_000..9_999_999),
      'sport_type' => 'Run',
      'name' => 'Morning Run',
      'start_date_local' => '2024-06-15T08:00:00Z',
      'distance' => 5000.0,
      'total_elevation_gain' => 100.0,
      'moving_time' => 1800,
      'calories' => 350.0,
      'location_state' => 'California',
      'location_country' => 'USA'
    }.merge(overrides)
  end

  def run_activity(date: '2024-06-15T08:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'Run',
      'name' => 'Morning Run',
      'start_date_local' => date,
      'distance' => 8000.0,
      'total_elevation_gain' => 150.0,
      'moving_time' => 2400,
      'calories' => 500.0
    }.merge(overrides))
  end

  def ride_activity(date: '2024-06-15T09:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'Ride',
      'name' => 'Afternoon Ride',
      'start_date_local' => date,
      'distance' => 30000.0,
      'total_elevation_gain' => 500.0,
      'moving_time' => 5400,
      'calories' => 800.0
    }.merge(overrides))
  end

  def snowboard_activity(date: '2024-01-15T10:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'Snowboard',
      'name' => 'Powder Day',
      'start_date_local' => date,
      'distance' => 15000.0,
      'total_elevation_gain' => 1500.0,
      'moving_time' => 14400,
      'calories' => 1200.0,
      'location_state' => 'Colorado',
      'location_country' => 'USA'
    }.merge(overrides))
  end

  def alpine_ski_activity(date: '2024-01-20T09:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'AlpineSki',
      'name' => 'Ski Day',
      'start_date_local' => date,
      'distance' => 20000.0,
      'total_elevation_gain' => 2000.0,
      'moving_time' => 18000,
      'calories' => 1500.0,
      'location_state' => 'Utah',
      'location_country' => 'USA'
    }.merge(overrides))
  end

  def backcountry_ski_activity(date: '2024-02-10T07:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'BackcountrySki',
      'name' => 'Backcountry Tour',
      'start_date_local' => date,
      'distance' => 8000.0,
      'total_elevation_gain' => 1000.0,
      'moving_time' => 10800,
      'calories' => 900.0,
      'location_state' => 'Colorado',
      'location_country' => 'USA'
    }.merge(overrides))
  end

  def snowshoe_activity(date: '2024-12-20T10:00:00Z', **overrides)
    base_activity({
      'sport_type' => 'Snowshoe',
      'name' => 'Snowshoe Hike',
      'start_date_local' => date,
      'distance' => 5000.0,
      'total_elevation_gain' => 300.0,
      'moving_time' => 7200,
      'calories' => 400.0
    }.merge(overrides))
  end

  def mixed_activities_2024
    [
      run_activity(date: '2024-03-15T08:00:00Z'),
      run_activity(date: '2024-06-20T07:00:00Z'),
      ride_activity(date: '2024-05-10T09:00:00Z'),
      ride_activity(date: '2024-07-15T08:00:00Z'),
      snowboard_activity(date: '2024-01-15T10:00:00Z'),
      snowboard_activity(date: '2024-02-20T09:00:00Z'),
      alpine_ski_activity(date: '2024-01-25T09:00:00Z')
    ]
  end

  def winter_activities_multiple_seasons
    [
      # 2023-24 season (Sep 2023 - Aug 2024)
      snowboard_activity(date: '2023-12-15T10:00:00Z', 'id' => 1001),
      snowboard_activity(date: '2024-01-10T10:00:00Z', 'id' => 1002),
      alpine_ski_activity(date: '2024-02-05T09:00:00Z', 'id' => 1003),
      backcountry_ski_activity(date: '2024-03-01T07:00:00Z', 'id' => 1004),
      # 2024-25 season (Sep 2024 - Aug 2025)
      snowboard_activity(date: '2024-11-20T10:00:00Z', 'id' => 2001),
      snowboard_activity(date: '2024-12-25T10:00:00Z', 'id' => 2002),
      alpine_ski_activity(date: '2025-01-15T09:00:00Z', 'id' => 2003)
    ]
  end

  def activities_multiple_years
    [
      run_activity(date: '2022-05-15T08:00:00Z', 'id' => 101),
      run_activity(date: '2022-08-20T07:00:00Z', 'id' => 102),
      ride_activity(date: '2023-04-10T09:00:00Z', 'id' => 201),
      ride_activity(date: '2023-07-15T08:00:00Z', 'id' => 202),
      run_activity(date: '2024-03-15T08:00:00Z', 'id' => 301),
      run_activity(date: '2024-06-20T07:00:00Z', 'id' => 302),
      ride_activity(date: '2024-05-10T09:00:00Z', 'id' => 303)
    ]
  end

  def activity_with_missing_fields
    {
      'id' => 999999,
      'sport_type' => 'Run',
      'start_date_local' => '2024-06-15T08:00:00Z'
      # Missing: name, distance, total_elevation_gain, moving_time, calories
    }
  end

  def mock_resort(name: 'Test Resort', resort_type: 'resort')
    {
      'id' => rand(1..1000),
      'name' => name,
      'resort_type' => resort_type,
      'country' => 'USA',
      'region' => 'Colorado'
    }
  end

  def mock_peak(name: 'Test Peak')
    {
      'id' => rand(1..1000),
      'name' => name,
      'country' => 'USA',
      'region' => 'Colorado',
      'elevation_m' => 4000
    }
  end
end
