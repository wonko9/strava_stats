# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'strava_stats/logging'
require_relative 'strava_stats/html/formatters'
require_relative 'strava_stats/html/chart_data_builder'
require_relative 'strava_stats/html/styles'
require_relative 'strava_stats/html/scripts'
require_relative 'strava_stats/html/sections'

module StravaStats
  # Generates HTML stats pages from activity statistics.
  # Orchestrates the HTML generation by delegating to specialized modules:
  # - Styles: CSS styling
  # - Scripts: JavaScript functionality
  # - Sections: HTML section generators
  # - ChartDataBuilder: Chart.js data preparation
  class HTMLGenerator
    include Logging
    include HTML::Formatters

    # Re-export constants for backward compatibility
    SPORT_COLORS = HTML::Formatters::SPORT_COLORS
    DEFAULT_COLOR = HTML::Formatters::DEFAULT_COLOR

    def initialize(output_path:)
      @output_path = output_path
      @chart_builder = HTML::ChartDataBuilder.new
    end

    def generate(stats:, athlete_name: nil)
      html = build_html(stats, athlete_name)

      FileUtils.mkdir_p(File.dirname(@output_path))
      File.write(@output_path, html)

      logger.info "Generated stats page: #{@output_path}"
      @output_path
    end

    private

    def build_html(stats, athlete_name)
      # Prepare chart data
      by_year_chart = @chart_builder.prepare_by_year_chart(stats[:by_year])
      by_sport_chart = @chart_builder.prepare_by_sport_chart(stats[:by_sport])
      winter_season_chart = @chart_builder.prepare_winter_season_chart(stats[:winter_by_season])
      all_activities = @chart_builder.collect_all_activities(stats)

      # Generate JavaScript with embedded data
      scripts = HTML::Scripts.generate(
        stats: stats,
        by_year_chart: by_year_chart,
        by_sport_chart: by_sport_chart,
        winter_season_chart: winter_season_chart,
        all_activities: all_activities
      )

      build_page(stats, athlete_name, scripts)
    end

    def build_page(stats, athlete_name, scripts)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{athlete_name ? "#{athlete_name}'s " : ''}Strava Stats</title>
          <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%23FC4C02'/><path d='M8 22 L12 12 L16 18 L20 8 L24 22' stroke='white' stroke-width='3' fill='none' stroke-linecap='round' stroke-linejoin='round'/></svg>">
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>#{HTML::Styles.css}</style>
        </head>
        <body>
          <div class="container">
            #{header_section(stats, athlete_name)}
            #{HTML::Sections.summary_section(stats[:summary])}
            #{HTML::Sections.charts_section}
            #{HTML::Sections.sports_section(stats[:by_sport])}
            #{HTML::Sections.years_section(stats[:by_year], stats[:by_sport_and_year])}
            #{year_comparison_section(stats[:year_comparisons])}
            #{winter_section(stats[:winter_by_season])}
            #{season_comparison_section(stats[:season_comparisons])}
            #{resorts_section(stats[:resorts_by_season])}
            #{peaks_section(stats[:peaks_by_season])}
            #{HTML::Sections.activity_modal}
            <p class="generated-at">Generated #{Time.now.strftime('%B %d, %Y at %H:%M')}</p>
          </div>
          <script>#{scripts}</script>
        </body>
        </html>
      HTML
    end

    def header_section(stats, athlete_name)
      date_range = if stats[:summary][:date_range]
                     "#{format_date(stats[:summary][:date_range][:first])} - #{format_date(stats[:summary][:date_range][:last])}"
                   else
                     'No activities yet'
                   end

      <<~HTML
        <header>
          <h1>#{athlete_name ? "#{athlete_name}'s " : ''}Strava Stats</h1>
          <p class="subtitle">#{date_range}</p>
        </header>
      HTML
    end

    def year_comparison_section(year_comparisons)
      return '' if year_comparisons.empty?

      sports = year_comparisons.keys.sort
      sport_options = sports.map { |s| "<option value=\"#{s}\">#{format_sport_name(s)}</option>" }.join

      # Strip activities from comparison data - they're accessed via activityIds instead
      stripped_comparisons = strip_activities_from_comparisons(year_comparisons)

      <<~HTML
        <div class="section">
          <h2>Year-over-Year Comparison</h2>
          <div id="year-comparison-container" data-comparisons='#{stripped_comparisons.to_json}'>
            <div class="comparison-selectors">
              <div><label>Sport:</label><select id="yearComparisonSport" onchange="onYearSportChange()">#{sport_options}</select></div>
              <div class="year-selectors">
                <select id="yearComparisonYear1" onchange="updateYearComparisonDisplay()"></select>
                <span>vs</span>
                <select id="yearComparisonYear2" onchange="updateYearComparisonDisplay()"></select>
              </div>
            </div>
            #{comparison_grid('year')}
            #{comparison_chart('year')}
          </div>
        </div>
      HTML
    end

    def season_comparison_section(season_comparisons)
      return '' if season_comparisons.empty?

      sports = season_comparisons.keys.sort
      sport_options = sports.map { |s| "<option value=\"#{s}\">#{format_sport_name(s)}</option>" }.join

      # Strip activities from comparison data - they're accessed via activityIds instead
      stripped_comparisons = strip_activities_from_comparisons(season_comparisons)

      <<~HTML
        <div class="section">
          <h2>Season-over-Season Comparison</h2>
          <div id="season-comparison-container" data-comparisons='#{stripped_comparisons.to_json}'>
            <div class="comparison-selectors">
              <div><label>Sport:</label><select id="seasonComparisonSport" onchange="onSeasonSportChange()">#{sport_options}</select></div>
              <div class="year-selectors">
                <select id="seasonComparisonSeason1" onchange="updateSeasonComparisonDisplay()"></select>
                <span>vs</span>
                <select id="seasonComparisonSeason2" onchange="updateSeasonComparisonDisplay()"></select>
              </div>
            </div>
            #{comparison_grid('season')}
            #{comparison_chart('season')}
          </div>
        </div>
      HTML
    end

    def comparison_grid(type)
      <<~HTML
        <div class="comparison-grid">
          <div class="comparison-card current clickable" onclick="show#{type.capitalize}ComparisonActivities(1)">
            <h4 id="#{type}-comparison-label1"></h4>
            <div id="#{type}-comparison-stats1"></div>
          </div>
          <div class="comparison-vs">
            <span class="comparison-vs-header">Change</span>
            <div id="#{type}-comparison-changes"></div>
          </div>
          <div class="comparison-card clickable" onclick="show#{type.capitalize}ComparisonActivities(2)">
            <h4 id="#{type}-comparison-label2"></h4>
            <div id="#{type}-comparison-stats2"></div>
          </div>
        </div>
      HTML
    end

    def comparison_chart(type)
      <<~HTML
        <div class="comparison-chart-section">
          <div class="chart-controls">
            <label>Metric:</label>
            <select id="#{type}-comparison-metric" class="metric-selector" onchange="update#{type.capitalize}ComparisonChart()">
              <option value="activities" selected>Activities</option>
              <option value="hours">Hours</option>
              <option value="miles">Miles</option>
              <option value="elevation">Vertical (ft)</option>
              <option value="calories">Calories</option>
            </select>
          </div>
          <div style="height: 250px;"><canvas id="#{type}-comparison-chart"></canvas></div>
        </div>
      HTML
    end

    def winter_section(winter_by_season)
      return '' if winter_by_season.empty?

      all_sports = winter_by_season.values.flat_map { |d| d[:by_sport].keys }.uniq.sort
      sport_tabs = all_sports.map { |s| "<button class=\"tab#{s == all_sports.first ? ' active' : ''}\" onclick=\"showWinterTab('#{s}')\">#{format_sport_name(s)}</button>" }.join
      sport_tables = all_sports.map.with_index { |s, i| winter_stats_table(s, winter_by_season, hidden: i > 0) }.join

      <<~HTML
        <div class="section">
          <h2>Winter Sports by Season</h2>
          <div class="chart-container"><h3>Activities by Season</h3><canvas id="winterSeasonChart"></canvas></div>
          <div class="tabs" id="winterTabs">#{sport_tabs}</div>
          #{sport_tables}
        </div>
      HTML
    end

    def winter_stats_table(sport, winter_by_season, hidden: false)
      rows = winter_by_season.map do |season, data|
        stats = data[:by_sport][sport]
        next unless stats

        <<~HTML
          <tr class="clickable" onclick="showActivityModal('#{format_sport_name(sport)} - #{season}', getActivitiesFromIds(activityIds.winterBySeason['#{season}'] && activityIds.winterBySeason['#{season}'].by_sport['#{sport}'] || []))">
            <td data-sort="#{season}"><strong>#{season}</strong></td>
            <td class="number" data-sort="#{stats[:total_activities]}">#{format_number(stats[:total_activities])}</td>
            <td class="number" data-sort="#{stats[:total_days]}">#{format_number(stats[:total_days])}</td>
            <td class="number" data-sort="#{stats[:total_time_hours]}">#{format_number(stats[:total_time_hours])}</td>
            <td class="number" data-sort="#{stats[:total_distance_miles]}">#{format_number(stats[:total_distance_miles])}</td>
            <td class="number" data-sort="#{stats[:total_elevation_feet]}">#{format_number(stats[:total_elevation_feet])}</td>
            <td class="number" data-sort="#{stats[:total_calories]}">#{format_number(stats[:total_calories])}</td>
          </tr>
        HTML
      end.compact.join

      <<~HTML
        <div id="winter-#{sport}" class="winter-table#{hidden ? ' hidden' : ''}">
          <table class="sortable">
            <thead>
              <tr>
                <th>Season</th>
                <th class="number">Activities</th>
                <th class="number">Days</th>
                <th class="number">Hours</th>
                <th class="number">Miles</th>
                <th class="number">Vertical (ft)</th>
                <th class="number">Calories</th>
              </tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      HTML
    end

    def resorts_section(resorts_by_season)
      return '' if resorts_by_season.empty?

      seasons = resorts_by_season.map do |season, resorts|
        resort_cards = resorts.map do |name, data|
          stats = data[:stats]
          <<~HTML
            <div class="resort-card">
              <div class="resort-name">#{name}</div>
              <div class="resort-stats">#{stats[:total_activities]} activities &bull; #{stats[:total_days]} days &bull; #{format_number(stats[:total_elevation_feet])} ft</div>
            </div>
          HTML
        end.join

        <<~HTML
          <div class="resort-section">
            <h3>#{season} Season</h3>
            <div class="resort-grid">#{resort_cards}</div>
          </div>
        HTML
      end.join

      <<~HTML
        <div class="section">
          <h2>Ski Resorts</h2>
          #{seasons}
        </div>
      HTML
    end

    def peaks_section(peaks_by_season)
      return '' if peaks_by_season.empty?

      seasons = peaks_by_season.map do |season, peaks|
        peak_cards = peaks.map do |name, data|
          stats = data[:stats]
          elevation = data[:peak]['elevation_feet'] ? " (#{format_number(data[:peak]['elevation_feet'])} ft)" : ''
          <<~HTML
            <div class="resort-card">
              <div class="resort-name">#{name}#{elevation}</div>
              <div class="resort-stats">#{stats[:total_activities]} activities &bull; #{format_number(stats[:total_elevation_feet])} ft vert</div>
            </div>
          HTML
        end.join

        <<~HTML
          <div class="resort-section">
            <h3>#{season} Season</h3>
            <div class="resort-grid">#{peak_cards}</div>
          </div>
        HTML
      end.join

      <<~HTML
        <div class="section">
          <h2>Backcountry Peaks</h2>
          #{seasons}
        </div>
      HTML
    end

    # Remove activities array from comparison data to reduce HTML size
    # Activities are already available via activityIds and allActivities in JavaScript
    def strip_activities_from_comparisons(comparisons)
      comparisons.transform_values do |sport_data|
        result = sport_data.dup

        # Handle year comparisons (yearly_data key)
        if sport_data[:yearly_data]
          result[:yearly_data] = sport_data[:yearly_data].transform_values do |period_data|
            period_data.merge(
              stats: period_data[:stats]&.reject { |k, _| k == :activities }
            )
          end
        end

        # Handle season comparisons (season_data key)
        if sport_data[:season_data]
          result[:season_data] = sport_data[:season_data].transform_values do |period_data|
            period_data.merge(
              stats: period_data[:stats]&.reject { |k, _| k == :activities }
            )
          end
        end

        result
      end
    end
  end
end
