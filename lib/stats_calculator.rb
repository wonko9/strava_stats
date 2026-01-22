# frozen_string_literal: true

require 'time'
require 'set'

module StravaStats
  class StatsCalculator
    # Meters to miles conversion
    METERS_TO_MILES = 0.000621371
    # Meters to feet conversion
    METERS_TO_FEET = 3.28084
    # Seconds to hours conversion
    SECONDS_TO_HOURS = 1.0 / 3600

    WINTER_SPORTS = %w[
      Snowboard
      AlpineSki
      BackcountrySki
      NordicSki
      Snowshoe
    ].freeze

    def initialize(database:)
      @database = database
      @resorts_by_activity = {}
      @peaks_by_activity = {}
    end

    def calculate_all_stats
      activities = @database.get_all_activities
      by_sport_and_year = calculate_by_sport_and_year(activities)
      winter_by_season = calculate_winter_by_season(activities)

      # Prefetch resort and peak matches for all activities to avoid N+1 queries
      activity_ids = activities.map { |a| a['id'] }
      @resorts_by_activity = @database.get_resorts_for_activities(activity_ids)
      @peaks_by_activity = @database.get_peaks_for_activities(activity_ids)

      {
        summary: calculate_summary(activities),
        by_sport: calculate_by_sport(activities),
        by_year: calculate_by_year(activities),
        by_sport_and_year: by_sport_and_year,
        winter_by_season: winter_by_season,
        resorts_by_season: calculate_resorts_by_season(activities),
        backcountry_by_season: calculate_backcountry_by_season(activities),
        peaks_by_season: calculate_peaks_by_season(activities),
        year_comparisons: calculate_year_comparisons(by_sport_and_year),
        season_comparisons: calculate_season_comparisons(winter_by_season)
      }
    end

    def calculate_summary(activities)
      {
        total_activities: activities.count,
        total_sports: activities.map { |a| a['sport_type'] }.uniq.count,
        total_distance_miles: sum_distance_miles(activities),
        total_elevation_feet: sum_elevation_feet(activities),
        total_time_hours: sum_time_hours(activities),
        total_calories: sum_calories(activities),
        date_range: date_range(activities)
      }
    end

    def calculate_by_sport(activities)
      grouped = activities.group_by { |a| a['sport_type'] }

      grouped.transform_values do |sport_activities|
        calculate_sport_stats(sport_activities, include_activities: true)
      end.sort_by { |_, stats| -stats[:total_activities] }.to_h
    end

    def calculate_by_year(activities)
      grouped = activities.group_by { |a| extract_year(a['start_date_local']) }

      grouped.transform_values do |year_activities|
        calculate_sport_stats(year_activities, include_activities: true)
      end.sort_by { |year, _| year }.to_h
    end

    def calculate_by_sport_and_year(activities)
      result = {}

      activities.each do |activity|
        sport = activity['sport_type']
        year = extract_year(activity['start_date_local'])

        result[sport] ||= {}
        result[sport][year] ||= []
        result[sport][year] << activity
      end

      result.transform_values do |years|
        years.transform_values do |year_activities|
          calculate_sport_stats(year_activities, include_activities: true)
        end.sort_by { |year, _| year }.to_h
      end.sort_by { |sport, _| sport }.to_h
    end

    def calculate_winter_by_season(activities)
      winter_activities = activities.select { |a| WINTER_SPORTS.include?(a['sport_type']) }
      grouped = winter_activities.group_by { |a| extract_winter_season(a['start_date_local']) }

      grouped.transform_values do |season_activities|
        by_sport = season_activities.group_by { |a| a['sport_type'] }

        {
          totals: calculate_sport_stats(season_activities, include_activities: true),
          by_sport: by_sport.transform_values { |sa| calculate_sport_stats(sa, include_activities: true) }
        }
      end.sort_by { |season, _| season }.to_h
    end

    def calculate_resorts_by_season(activities)
      result = {}

      activities.each do |activity|
        next unless %w[Snowboard AlpineSki].include?(activity['sport_type'])

        # Use prefetched data instead of individual query
        resort = @resorts_by_activity[activity['id']]
        next unless resort && resort['resort_type'] != 'backcountry'

        season = extract_winter_season(activity['start_date_local'])
        result[season] ||= {}
        result[season][resort['name']] ||= {
          resort: resort,
          activities: [],
          stats: nil
        }
        result[season][resort['name']][:activities] << activity
      end

      # Calculate stats for each resort
      result.each do |season, resorts|
        resorts.each do |name, data|
          data[:stats] = calculate_sport_stats(data[:activities])
        end
        result[season] = resorts.sort_by { |name, _| name }.to_h
      end

      result.sort_by { |season, _| season }.to_h
    end

    def calculate_backcountry_by_season(activities)
      result = {}

      activities.each do |activity|
        next unless activity['sport_type'] == 'BackcountrySki'

        # Use prefetched data instead of individual query
        resort = @resorts_by_activity[activity['id']]
        region_name = if resort && resort['resort_type'] == 'backcountry'
                        resort['name']
                      elsif resort
                        "#{resort['name']} area"
                      else
                        activity['location_state'] || activity['location_country'] || 'Unknown'
                      end

        season = extract_winter_season(activity['start_date_local'])
        result[season] ||= {}
        result[season][region_name] ||= {
          activities: [],
          stats: nil
        }
        result[season][region_name][:activities] << activity
      end

      # Calculate stats for each region
      result.each do |season, regions|
        regions.each do |name, data|
          data[:stats] = calculate_sport_stats(data[:activities])
        end
        result[season] = regions.sort_by { |name, _| name }.to_h
      end

      result.sort_by { |season, _| season }.to_h
    end

    def calculate_peaks_by_season(activities)
      result = {}

      activities.each do |activity|
        next unless activity['sport_type'] == 'BackcountrySki'

        # Use prefetched data instead of individual query
        peak = @peaks_by_activity[activity['id']]
        next unless peak

        season = extract_winter_season(activity['start_date_local'])
        result[season] ||= {}
        result[season][peak['name']] ||= {
          peak: peak,
          activities: [],
          stats: nil
        }
        result[season][peak['name']][:activities] << activity
      end

      # Calculate stats for each peak
      result.each do |season, peaks|
        peaks.each do |name, data|
          data[:stats] = calculate_sport_stats(data[:activities])
        end
        result[season] = peaks.sort_by { |name, _| name }.to_h
      end

      result.sort_by { |season, _| season }.to_h
    end

    def calculate_year_comparisons(by_sport_and_year)
      current_year = Time.now.year
      current_day_of_year = Time.now.yday

      # Get all activities for cumulative calculations
      all_activities = @database.get_all_activities

      # Get all years that have data across all sports
      all_years = by_sport_and_year.values.flat_map(&:keys).uniq
      # Always include current year
      all_years << current_year unless all_years.include?(current_year)
      all_years = all_years.sort.reverse

      result = {}

      by_sport_and_year.each do |sport, years|
        sport_years = years.keys
        # Always include current year for every sport
        sport_years << current_year unless sport_years.include?(current_year)
        sport_years = sport_years.sort.reverse
        next if sport_years.empty?

        # Calculate cumulative for all years this sport has data
        sport_activities = all_activities.select { |a| a['sport_type'] == sport }

        yearly_data = {}
        sport_years.each do |year|
          cumulative = calculate_yearly_cumulative(sport_activities, year)

          yearly_data[year] = {
            stats: years[year] || empty_stats,
            cumulative: cumulative,
            cumulative_clipped: cumulative  # Show full year data for all years
          }
        end

        result[sport] = {
          available_years: sport_years,
          current_year: current_year,
          current_day: current_day_of_year,
          yearly_data: yearly_data
        }
      end

      result.sort_by { |sport, _| sport }.to_h
    end

    def calculate_season_comparisons(winter_by_season)
      current_season = extract_winter_season(Time.now.to_s)
      current_start_year = current_season.split('-').first.to_i

      # Calculate current day of season for clipping
      season_start = Time.new(current_start_year, 9, 1)
      current_day_of_season = ((Time.now - season_start) / 86400).to_i

      # Get all activities for cumulative calculations
      all_activities = @database.get_all_activities

      # Get all seasons that have data
      all_seasons = winter_by_season.keys
      # Always include current season
      all_seasons << current_season unless all_seasons.include?(current_season)
      all_seasons = all_seasons.sort.reverse

      result = {}

      # Get all winter sports that have data
      all_sports = winter_by_season.values.flat_map { |d| d[:by_sport].keys }.uniq

      all_sports.each do |sport|
        # Get seasons that have data for this sport
        sport_seasons = all_seasons.select { |s| winter_by_season.dig(s, :by_sport, sport) }
        # Always include current season for every sport
        sport_seasons << current_season unless sport_seasons.include?(current_season)
        sport_seasons = sport_seasons.sort.reverse
        next if sport_seasons.empty?

        sport_activities = all_activities.select { |a| a['sport_type'] == sport }

        season_data = {}
        sport_seasons.each do |season|
          cumulative = calculate_season_cumulative(sport_activities, season)

          season_data[season] = {
            stats: winter_by_season.dig(season, :by_sport, sport) || empty_stats,
            cumulative: cumulative,
            cumulative_clipped: cumulative  # Show full season data for all seasons
          }
        end

        result[sport] = {
          available_seasons: sport_seasons,
          current_season: current_season,
          current_day: current_day_of_season,
          season_data: season_data
        }
      end

      result.sort_by { |sport, _| sport }.to_h
    end

    private

    def empty_stats
      {
        total_activities: 0,
        total_days: 0,
        total_distance_miles: 0,
        total_elevation_feet: 0,
        total_time_hours: 0,
        total_calories: 0
      }
    end

    def calculate_changes(current, previous)
      changes = {}

      %i[total_activities total_days total_distance_miles total_elevation_feet total_time_hours total_calories].each do |key|
        curr_val = current[key] || 0
        prev_val = previous[key] || 0
        diff = curr_val - prev_val

        pct = if prev_val.zero?
                curr_val.zero? ? 0 : 100
              else
                ((diff.to_f / prev_val) * 100).round(0)
              end

        changes[key] = { diff: diff, pct: pct }
      end

      changes
    end

    # Calculate cumulative stats by day of year for line chart
    def calculate_yearly_cumulative(activities, year)
      year_activities = activities.select do |a|
        date = a['start_date_local']
        date && extract_year(date) == year
      end

      return [] if year_activities.empty?

      # Sort by date
      sorted = year_activities.sort_by { |a| a['start_date_local'] }

      cumulative = []
      running_totals = { activities: 0, hours: 0.0, miles: 0.0, elevation: 0, calories: 0 }

      sorted.each do |activity|
        date = Time.parse(activity['start_date_local'])
        day_of_year = date.yday

        running_totals[:activities] += 1
        running_totals[:hours] += (activity['moving_time'] || 0) * SECONDS_TO_HOURS
        running_totals[:miles] += (activity['distance'] || 0) * METERS_TO_MILES
        running_totals[:elevation] += ((activity['total_elevation_gain'] || 0) * METERS_TO_FEET).round(0)
        running_totals[:calories] += (activity['calories'] || 0).round(0)

        cumulative << {
          day: day_of_year,
          date: date.strftime('%b %d'),
          activities: running_totals[:activities],
          hours: running_totals[:hours].round(1),
          miles: running_totals[:miles].round(1),
          elevation: running_totals[:elevation],
          calories: running_totals[:calories]
        }
      end

      cumulative
    end

    # Calculate cumulative stats by day of season for line chart
    # Season runs Sep 1 - Aug 31
    def calculate_season_cumulative(activities, season)
      season_activities = activities.select do |a|
        date = a['start_date_local']
        date && extract_winter_season(date) == season
      end

      return [] if season_activities.empty?

      # Parse season start year (e.g., "2024-25" -> 2024)
      season_start_year = season.split('-').first.to_i
      season_start = Time.new(season_start_year, 9, 1)

      # Sort by date
      sorted = season_activities.sort_by { |a| a['start_date_local'] }

      cumulative = []
      running_totals = { activities: 0, hours: 0.0, miles: 0.0, elevation: 0, calories: 0 }

      sorted.each do |activity|
        date = Time.parse(activity['start_date_local'])
        # Day of season (0 = Sep 1)
        day_of_season = (date - season_start).to_i / 86400

        running_totals[:activities] += 1
        running_totals[:hours] += (activity['moving_time'] || 0) * SECONDS_TO_HOURS
        running_totals[:miles] += (activity['distance'] || 0) * METERS_TO_MILES
        running_totals[:elevation] += ((activity['total_elevation_gain'] || 0) * METERS_TO_FEET).round(0)
        running_totals[:calories] += (activity['calories'] || 0).round(0)

        cumulative << {
          day: day_of_season,
          date: date.strftime('%b %d'),
          activities: running_totals[:activities],
          hours: running_totals[:hours].round(1),
          miles: running_totals[:miles].round(1),
          elevation: running_totals[:elevation],
          calories: running_totals[:calories]
        }
      end

      cumulative
    end

    def calculate_sport_stats(activities, include_activities: false)
      days = activities.map { |a| extract_date(a['start_date_local']) }.uniq

      result = {
        total_activities: activities.count,
        total_days: days.count,
        total_distance_miles: sum_distance_miles(activities),
        total_elevation_feet: sum_elevation_feet(activities),
        total_time_hours: sum_time_hours(activities),
        total_calories: sum_calories(activities)
      }

      if include_activities
        result[:activities] = activities.map { |a| activity_summary(a) }
      end

      result
    end

    def activity_summary(activity)
      {
        id: activity['id'],
        name: activity['name'] || 'Activity',
        date: activity['start_date_local']&.split('T')&.first || '',
        elevation: ((activity['total_elevation_gain'] || 0) * METERS_TO_FEET).round(0),
        hours: ((activity['moving_time'] || 0) * SECONDS_TO_HOURS).round(2),
        miles: ((activity['distance'] || 0) * METERS_TO_MILES).round(1),
        calories: (activity['calories'] || 0).round(0)
      }
    end

    def sum_distance_miles(activities)
      total_meters = activities.sum { |a| a['distance'] || 0 }
      (total_meters * METERS_TO_MILES).round(1)
    end

    def sum_elevation_feet(activities)
      total_meters = activities.sum { |a| a['total_elevation_gain'] || 0 }
      (total_meters * METERS_TO_FEET).round(0)
    end

    def sum_time_hours(activities)
      total_seconds = activities.sum { |a| a['moving_time'] || 0 }
      (total_seconds * SECONDS_TO_HOURS).round(1)
    end

    def sum_calories(activities)
      activities.sum { |a| a['calories'] || 0 }.round(0)
    end

    def date_range(activities)
      return nil if activities.empty?

      dates = activities.map { |a| a['start_date_local'] }.compact.sort
      return nil if dates.empty?

      {
        first: dates.first,
        last: dates.last
      }
    end

    def extract_year(date_string)
      return nil unless date_string

      Time.parse(date_string).year
    end

    def extract_date(date_string)
      return nil unless date_string

      Time.parse(date_string).strftime('%Y-%m-%d')
    end

    # Winter season runs September through August
    # e.g., "2023-24" covers Sep 2023 - Aug 2024
    def extract_winter_season(date_string)
      return nil unless date_string

      date = Time.parse(date_string)
      year = date.year
      month = date.month

      if month >= 9
        # Sep-Dec belongs to season starting this year
        "#{year}-#{(year + 1) % 100}"
      else
        # Jan-Aug belongs to season that started previous year
        "#{year - 1}-#{year % 100}"
      end
    end
  end
end
