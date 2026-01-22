# frozen_string_literal: true

require 'erb'
require 'json'
require 'fileutils'
require_relative 'strava_stats/logging'
require_relative 'strava_stats/html/formatters'
require_relative 'strava_stats/html/chart_data_builder'

module StravaStats
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
      # Use extracted chart builder for data preparation
      by_year_chart = @chart_builder.prepare_by_year_chart(stats[:by_year])
      by_sport_chart = @chart_builder.prepare_by_sport_chart(stats[:by_sport])
      sport_by_year_charts = @chart_builder.prepare_sport_by_year_charts(stats[:by_sport_and_year])
      winter_season_chart = @chart_builder.prepare_winter_season_chart(stats[:winter_by_season])

      # Build HTML (keeping existing template structure)
      build_html_content(stats, athlete_name, by_year_chart, by_sport_chart, sport_by_year_charts, winter_season_chart)
    end

    def build_html_content(stats, athlete_name, by_year_chart, by_sport_chart, sport_by_year_charts, winter_season_chart)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{athlete_name ? "#{athlete_name}'s " : ''}Strava Stats</title>
          <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%23FC4C02'/><path d='M8 22 L12 12 L16 18 L20 8 L24 22' stroke='white' stroke-width='3' fill='none' stroke-linecap='round' stroke-linejoin='round'/></svg>">
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>
            :root {
              --bg-primary: #f7f7fa;
              --bg-secondary: #ffffff;
              --bg-card: #ffffff;
              --text-primary: #242428;
              --text-secondary: #6d6d78;
              --accent: #FC4C02;
              --accent-hover: #e04400;
              --border: #dfdfe8;
              --shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
            }

            * {
              margin: 0;
              padding: 0;
              box-sizing: border-box;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
              background: var(--bg-primary);
              color: var(--text-primary);
              line-height: 1.5;
              padding: 1.5rem;
              font-size: 14px;
            }

            .container {
              max-width: 1400px;
              margin: 0 auto;
            }

            header {
              text-align: center;
              margin-bottom: 1.5rem;
              padding-bottom: 1rem;
              border-bottom: 1px solid var(--border);
            }

            h1 {
              font-size: 1.75rem;
              margin-bottom: 0.25rem;
              color: var(--accent);
            }

            .subtitle {
              color: var(--text-secondary);
              font-size: 0.9rem;
            }

            h2 {
              font-size: 1.25rem;
              margin-bottom: 1rem;
              color: var(--text-primary);
              font-weight: 700;
              padding-bottom: 0.5rem;
              border-bottom: 3px solid var(--accent);
              display: inline-block;
            }

            h3 {
              font-size: 1rem;
              margin-bottom: 0.75rem;
              color: var(--text-primary);
              font-weight: 600;
            }

            .section {
              margin-bottom: 2rem;
            }

            .summary-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
              gap: 0.75rem;
              margin-bottom: 1rem;
            }

            .stat-card {
              background: var(--bg-card);
              border-radius: 8px;
              padding: 1rem;
              text-align: center;
              border: 1px solid var(--border);
              box-shadow: var(--shadow);
            }

            .stat-value {
              font-size: 1.5rem;
              font-weight: 700;
              color: var(--text-primary);
            }

            .stat-label {
              color: var(--text-secondary);
              font-size: 0.75rem;
              margin-top: 0.25rem;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }

            .chart-container {
              background: var(--bg-card);
              border-radius: 8px;
              padding: 1rem;
              margin-bottom: 1rem;
              border: 1px solid var(--border);
              box-shadow: var(--shadow);
            }

            .chart-row {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 0.75rem;
            }

            table {
              width: 100%;
              border-collapse: collapse;
              background: var(--bg-card);
              border-radius: 8px;
              overflow: hidden;
              border: 1px solid var(--border);
              font-size: 0.875rem;
              box-shadow: var(--shadow);
            }

            th, td {
              padding: 0.75rem 1rem;
              text-align: left;
              border-bottom: 1px solid var(--border);
            }

            th {
              background: var(--bg-primary);
              font-weight: 600;
              color: var(--text-secondary);
              font-size: 0.75rem;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }

            /* Sortable table headers */
            table.sortable th {
              cursor: pointer;
              user-select: none;
              position: relative;
              padding-right: 1.5rem;
            }

            table.sortable th:hover {
              color: var(--accent);
            }

            table.sortable th::after {
              content: '⇅';
              position: absolute;
              right: 0.5rem;
              opacity: 0.3;
              font-size: 0.65rem;
            }

            table.sortable th.sort-asc::after {
              content: '↑';
              opacity: 1;
              color: var(--accent);
            }

            table.sortable th.sort-desc::after {
              content: '↓';
              opacity: 1;
              color: var(--accent);
            }

            tr:last-child td {
              border-bottom: none;
            }

            tr:hover {
              background: #f7f7fa;
            }

            .number {
              text-align: right;
              font-variant-numeric: tabular-nums;
            }

            .sport-badge {
              display: inline-block;
              padding: 0.15rem 0.5rem;
              border-radius: 9999px;
              font-size: 0.75rem;
              font-weight: 500;
              color: white;
            }

            .resort-section {
              margin-top: 0.75rem;
            }

            .resort-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
              gap: 0.5rem;
            }

            .resort-card {
              background: var(--bg-card);
              border-radius: 6px;
              padding: 0.5rem 0.75rem;
              border: 1px solid var(--border);
            }

            .resort-name {
              font-weight: 600;
              margin-bottom: 0.25rem;
              color: var(--accent);
              font-size: 0.85rem;
            }

            .resort-stats {
              font-size: 0.75rem;
              color: var(--text-secondary);
            }

            .tabs {
              display: flex;
              gap: 0.5rem;
              margin-bottom: 1rem;
              flex-wrap: wrap;
              border-bottom: 1px solid var(--border);
              padding-bottom: 0;
            }

            .tab {
              padding: 0.5rem 1rem;
              background: transparent;
              border: none;
              border-bottom: 3px solid transparent;
              cursor: pointer;
              color: var(--text-secondary);
              transition: all 0.2s;
              font-size: 0.875rem;
              font-weight: 500;
              margin-bottom: -1px;
            }

            .tab:hover {
              color: var(--text-primary);
            }

            .tab.active {
              color: var(--accent);
              border-bottom-color: var(--accent);
            }

            .tab-content {
              display: none;
            }

            .tab-content.active {
              display: block;
            }

            .hidden {
              display: none;
            }

            .winter-table {
              margin-top: 0.5rem;
            }

            /* Comparison section styles */
            .comparison-container {
              margin-top: 0.5rem;
            }

            .comparison-grid {
              display: grid;
              grid-template-columns: 1fr auto 1fr;
              gap: 0.75rem;
              align-items: stretch;
            }

            .comparison-card {
              background: var(--bg-card);
              border-radius: 8px;
              padding: 1rem;
              border: 1px solid var(--border);
              display: flex;
              flex-direction: column;
              box-shadow: var(--shadow);
            }

            .comparison-card h4 {
              color: var(--text-secondary);
              font-size: 0.75rem;
              margin-bottom: 0;
              text-transform: uppercase;
              letter-spacing: 0.05em;
              height: 24px;
              line-height: 24px;
            }

            .comparison-card.current h4 {
              color: var(--accent);
            }

            .comparison-stat {
              display: flex;
              justify-content: space-between;
              align-items: center;
              border-bottom: 1px solid var(--border);
              font-size: 0.8rem;
              height: 28px;
            }

            .comparison-stat:last-child {
              border-bottom: none;
            }

            .comparison-stat-label {
              color: var(--text-secondary);
            }

            .comparison-stat-value {
              font-weight: 600;
              font-variant-numeric: tabular-nums;
            }

            .comparison-vs {
              display: flex;
              flex-direction: column;
              align-items: center;
              padding: 0.75rem 0.25rem;
            }

            .comparison-vs-header {
              color: var(--text-secondary);
              font-size: 0.75rem;
              font-weight: bold;
              height: 24px;
              line-height: 24px;
            }

            .change-indicators {
              display: flex;
              flex-direction: column;
              width: 100%;
            }

            .change-indicator {
              display: flex;
              align-items: center;
              justify-content: center;
              font-size: 0.65rem;
              white-space: nowrap;
              height: 28px;
              border-bottom: 1px solid var(--border);
            }

            .change-indicator:last-child {
              border-bottom: none;
            }

            .change-positive {
              color: #22c55e;
            }

            .change-negative {
              color: #ef4444;
            }

            .change-neutral {
              color: var(--text-secondary);
            }

            .sport-selector {
              margin-bottom: 0.5rem;
            }

            .sport-selector select {
              background: var(--bg-card);
              color: var(--text-primary);
              border: 1px solid var(--border);
              border-radius: 4px;
              padding: 0.25rem 0.5rem;
              font-size: 0.8rem;
              cursor: pointer;
            }

            .sport-selector select:focus {
              outline: none;
              border-color: var(--accent);
            }

            .comparison-selectors {
              display: flex;
              gap: 1rem;
              margin-bottom: 0.75rem;
              flex-wrap: wrap;
              align-items: center;
              font-size: 0.8rem;
            }

            .comparison-selectors label {
              color: var(--text-secondary);
              margin-right: 0.25rem;
            }

            .year-selectors {
              display: flex;
              align-items: center;
              gap: 0.5rem;
            }

            select {
              background: var(--bg-card);
              color: var(--text-primary);
              border: 1px solid var(--border);
              border-radius: 6px;
              padding: 0.5rem 0.75rem;
              font-size: 0.875rem;
              cursor: pointer;
              appearance: none;
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%236d6d78' d='M6 8L1 3h10z'/%3E%3C/svg%3E");
              background-repeat: no-repeat;
              background-position: right 0.5rem center;
              padding-right: 2rem;
            }

            select:focus {
              outline: none;
              border-color: var(--accent);
              box-shadow: 0 0 0 3px rgba(252, 76, 2, 0.1);
            }

            select:hover {
              border-color: #b8b8c0;
            }

            .year-selectors span {
              color: var(--text-secondary);
            }

            .comparison-chart-section {
              margin-top: 1rem;
              background: var(--bg-card);
              border-radius: 8px;
              padding: 1rem;
              border: 1px solid var(--border);
              box-shadow: var(--shadow);
            }

            .chart-controls {
              margin-bottom: 0.5rem;
              display: flex;
              align-items: center;
              gap: 0.35rem;
              font-size: 0.8rem;
            }

            .chart-controls label {
              color: var(--text-secondary);
            }

            .metric-selector {
              background: var(--bg-secondary);
              color: var(--text-primary);
              border: 1px solid var(--border);
              border-radius: 4px;
              padding: 0.2rem 0.5rem;
              font-size: 0.8rem;
              cursor: pointer;
            }

            .metric-selector:focus {
              outline: none;
              border-color: var(--accent);
            }

            @media (max-width: 768px) {
              .comparison-grid {
                grid-template-columns: 1fr;
              }

              .comparison-vs {
                flex-direction: row;
                padding: 0.25rem;
              }
            }

            .generated-at {
              text-align: center;
              color: var(--text-secondary);
              font-size: 0.75rem;
              margin-top: 1.5rem;
              padding-top: 1rem;
              border-top: 1px solid var(--border);
            }

            .chart-tabs {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 0.5rem;
              flex-wrap: wrap;
              gap: 0.5rem;
            }

            .chart-metric-selector {
              display: flex;
              align-items: center;
              gap: 0.35rem;
              font-size: 0.8rem;
            }

            .chart-metric-selector label {
              color: var(--text-secondary);
            }

            .chart-metric-selector select {
              background: var(--bg-card);
              color: var(--text-primary);
              border: 1px solid var(--border);
              border-radius: 4px;
              padding: 0.25rem 0.5rem;
              font-size: 0.8rem;
              cursor: pointer;
            }

            @media (max-width: 768px) {
              body {
                padding: 0.5rem;
              }

              h1 {
                font-size: 1.4rem;
              }

              .chart-row {
                grid-template-columns: 1fr;
              }

              .summary-grid {
                grid-template-columns: repeat(3, 1fr);
              }
            }

            /* Activity Modal Styles */
            .modal-overlay {
              display: none;
              position: fixed;
              top: 0;
              left: 0;
              width: 100%;
              height: 100%;
              background: rgba(0, 0, 0, 0.5);
              z-index: 1000;
              justify-content: center;
              align-items: center;
              padding: 1rem;
            }

            .modal-overlay.active {
              display: flex;
            }

            .modal {
              background: var(--bg-secondary);
              border-radius: 12px;
              max-width: 700px;
              width: 100%;
              max-height: 80vh;
              overflow: hidden;
              border: 1px solid var(--border);
              display: flex;
              flex-direction: column;
              box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            }

            .modal-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              padding: 1.25rem 1.5rem;
              border-bottom: 1px solid var(--border);
              background: var(--bg-card);
            }

            .modal-title {
              font-size: 1.25rem;
              font-weight: 700;
              color: var(--text-primary);
            }

            .modal-close {
              background: none;
              border: none;
              color: var(--text-secondary);
              font-size: 1.75rem;
              cursor: pointer;
              padding: 0;
              line-height: 1;
            }

            .modal-close:hover {
              color: var(--accent);
            }

            .modal-body {
              padding: 1rem 1.5rem;
              overflow-y: auto;
              flex: 1;
              background: var(--bg-primary);
            }

            .activity-list {
              display: flex;
              flex-direction: column;
              gap: 0.75rem;
            }

            .activity-item {
              display: flex;
              justify-content: space-between;
              align-items: center;
              padding: 1rem;
              background: var(--bg-card);
              border-radius: 8px;
              border: 1px solid var(--border);
              text-decoration: none;
              color: var(--text-primary);
              transition: all 0.2s;
              box-shadow: var(--shadow);
            }

            .activity-item:hover {
              border-color: var(--accent);
              box-shadow: 0 2px 8px rgba(252, 76, 2, 0.15);
              transform: translateY(-1px);
            }

            .activity-info {
              display: flex;
              flex-direction: column;
              gap: 0.25rem;
            }

            .activity-name {
              font-weight: 600;
              color: var(--text-primary);
            }

            .activity-date {
              font-size: 0.8rem;
              color: var(--text-secondary);
            }

            .activity-stats {
              text-align: right;
              font-size: 0.875rem;
              color: var(--text-secondary);
            }

            .activity-stats span {
              display: block;
            }

            .strava-link {
              color: var(--accent);
              font-size: 0.75rem;
              margin-top: 0.25rem;
              font-weight: 500;
            }

            /* Clickable table rows */
            tr.clickable {
              cursor: pointer;
              transition: all 0.2s;
            }

            tr.clickable:hover {
              background: rgba(252, 76, 2, 0.08) !important;
            }

            /* Expandable sport chart row */
            tr.sport-chart-row {
              display: none;
            }

            tr.sport-chart-row.active {
              display: table-row;
            }

            tr.sport-chart-row td {
              padding: 1rem;
              background: var(--bg-primary);
            }

            .sport-chart-container {
              background: var(--bg-card);
              border-radius: 8px;
              padding: 1rem;
              border: 1px solid var(--border);
            }

            .sport-chart-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 0.75rem;
            }

            .sport-chart-title {
              font-weight: 600;
              color: var(--text-primary);
            }

            tr.sport-row-expanded {
              background: rgba(252, 76, 2, 0.05);
            }

            .expand-indicator {
              color: var(--text-secondary);
              font-size: 0.75rem;
              margin-left: 0.5rem;
            }

            tr.sport-row-expanded .expand-indicator::after {
              content: '▼';
            }

            tr:not(.sport-row-expanded) .expand-indicator::after {
              content: '▶';
            }

            /* Clickable cards */
            .comparison-card.clickable {
              cursor: pointer;
              transition: all 0.2s;
            }

            .comparison-card.clickable:hover {
              border-color: var(--accent);
              box-shadow: 0 2px 8px rgba(252, 76, 2, 0.15);
            }
          </style>
        </head>
        <body>
          <div class="container">
            <header>
              <h1>#{athlete_name ? "#{athlete_name}'s " : ''}Strava Stats</h1>
              <p class="subtitle">#{stats[:summary][:date_range] ? "#{format_date(stats[:summary][:date_range][:first])} - #{format_date(stats[:summary][:date_range][:last])}" : 'No activities yet'}</p>
            </header>

            <!-- Summary Section -->
            <div class="section">
              <h2>All-Time Summary</h2>
              <div class="summary-grid">
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_activities])}</div>
                  <div class="stat-label">Total Activities</div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_sports])}</div>
                  <div class="stat-label">Sports</div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_distance_miles])}</div>
                  <div class="stat-label">Total Miles</div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_elevation_feet])}</div>
                  <div class="stat-label">Total Vertical (ft)</div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_time_hours])}</div>
                  <div class="stat-label">Total Hours</div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">#{format_number(stats[:summary][:total_calories])}</div>
                  <div class="stat-label">Total Calories</div>
                </div>
              </div>
            </div>

            <!-- Charts Section -->
            <div class="section">
              <h2>Overview Charts</h2>
              <div class="chart-row">
                <div class="chart-container">
                  <h3>Activities by Year</h3>
                  <canvas id="byYearChart"></canvas>
                </div>
                <div class="chart-container" style="max-width: 400px;">
                  <h3>Activities by Sport</h3>
                  <canvas id="bySportChart"></canvas>
                </div>
              </div>
            </div>

            <!-- Stats by Sport -->
            <div class="section">
              <h2>Stats by Sport</h2>
              <p class="subtitle" style="margin-bottom: 0.75rem; color: var(--text-secondary);">Click any row to see yearly breakdown</p>
              <table class="sortable">
                <thead>
                  <tr>
                    <th>Sport</th>
                    <th class="number">Activities</th>
                    <th class="number">Days</th>
                    <th class="number">Hours</th>
                    <th class="number">Miles</th>
                    <th class="number">Vertical (ft)</th>
                    <th class="number">Calories</th>
                    <th class="number">Cal/hr</th>
                    <th class="number">Cal/activity</th>
                  </tr>
                </thead>
                <tbody>
                  #{stats[:by_sport].map { |sport, s| sport_row(sport, s) }.join("\n")}
                </tbody>
              </table>
            </div>

            <!-- Stats by Year -->
            <div class="section">
              <h2>Stats by Year</h2>
              <div class="sport-selector" style="margin-bottom: 1rem;">
                <label>Sport:</label>
                <select id="sportYearSelect" onchange="showSportTab(this.value)">
                  <option value="All">All</option>
                  #{stats[:by_sport_and_year].sort_by { |_, years| -years.values.sum { |s| s[:total_activities] } }.map { |sport, _| "<option value=\"#{sport}\">#{format_sport_name(sport)}</option>" }.join("\n")}
                </select>
              </div>
              #{all_years_tab(stats[:by_year])}
              #{stats[:by_sport_and_year].sort_by { |_, years| -years.values.sum { |s| s[:total_activities] } }.map { |sport, years| sport_year_tab(sport, years, false) }.join("\n")}
            </div>

            <!-- Year-over-Year Comparison -->
            #{year_comparison_section(stats[:year_comparisons])}

            <!-- Winter Sports by Season -->
            #{winter_section(stats[:winter_by_season])}

            <!-- Winter Season Comparison -->
            #{season_comparison_section(stats[:season_comparisons])}

            <!-- Resorts by Season -->
            #{resorts_section(stats[:resorts_by_season])}

            <!-- Backcountry Peaks by Season -->
            #{peaks_section(stats[:peaks_by_season])}

            <!-- Activity Modal -->
            <div id="activityModal" class="modal-overlay" onclick="if(event.target === this) closeActivityModal()">
              <div class="modal">
                <div class="modal-header">
                  <span class="modal-title" id="modalTitle">Activities</span>
                  <button class="modal-close" onclick="closeActivityModal()">&times;</button>
                </div>
                <div class="modal-body">
                  <div id="activityList" class="activity-list"></div>
                </div>
              </div>
            </div>

            <p class="generated-at">Generated #{Time.now.strftime('%B %d, %Y at %H:%M')}</p>
          </div>

          <script>
            // All activities stored once by ID
            var allActivities = #{collect_all_activities(stats).to_json};

            // Activity IDs grouped for lookups
            var activityIds = {
              bySport: #{stats[:by_sport].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } }.to_json},
              byYear: #{stats[:by_year].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } }.to_json},
              bySportAndYear: #{stats[:by_sport_and_year].transform_values { |years| years.transform_values { |s| (s[:activities] || []).map { |a| a[:id] } } }.to_json},
              winterBySeason: #{stats[:winter_by_season].transform_values { |d| { totals: (d[:totals][:activities] || []).map { |a| a[:id] }, by_sport: d[:by_sport].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } } } }.to_json}
            };

            // Yearly stats by sport for expandable charts
            var sportYearlyStats = #{stats[:by_sport_and_year].transform_values { |years| years.transform_values { |s| s.reject { |k, _| k == :activities } } }.to_json};

            // Helper to get activities from IDs
            function getActivitiesFromIds(ids) {
              return (ids || []).map(id => allActivities[id]).filter(a => a);
            }

            // Sport chart instances
            var sportCharts = {};

            function toggleSportChart(sport) {
              const row = document.getElementById('sport-row-' + sport);
              const chartRow = document.getElementById('sport-chart-row-' + sport);

              if (chartRow.classList.contains('active')) {
                // Collapse
                chartRow.classList.remove('active');
                row.classList.remove('sport-row-expanded');
              } else {
                // Expand
                chartRow.classList.add('active');
                row.classList.add('sport-row-expanded');
                // Render chart if not already done
                if (!sportCharts[sport]) {
                  renderSportChart(sport);
                }
              }
            }

            function renderSportChart(sport) {
              const data = sportYearlyStats[sport];
              if (!data) return;

              const metric = document.getElementById('sport-chart-metric-' + sport).value;
              const years = Object.keys(data).sort();
              const values = years.map(y => data[y][metric] || 0);
              const color = getSportColor(sport);

              const ctx = document.getElementById('sport-chart-' + sport).getContext('2d');
              sportCharts[sport] = new Chart(ctx, {
                type: 'bar',
                data: {
                  labels: years,
                  datasets: [{
                    label: getMetricLabel(metric),
                    data: values,
                    backgroundColor: color
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: {
                    legend: { display: false },
                    tooltip: {
                      callbacks: {
                        title: function(tooltipItems) {
                          return tooltipItems[0].label;
                        },
                        beforeLabel: function() { return null; },
                        label: function(tooltipItem) {
                          const currentMetric = document.getElementById('sport-chart-metric-' + sport).value;
                          const metricLabels = {
                            'total_activities': 'Total Activities',
                            'total_days': 'Total Days',
                            'total_time_hours': 'Total Hours',
                            'total_distance_miles': 'Total Miles',
                            'total_elevation_feet': 'Total Vertical (ft)',
                            'total_calories': 'Total Calories'
                          };
                          const label = metricLabels[currentMetric] || currentMetric;
                          return label + ': ' + tooltipItem.raw.toLocaleString();
                        },
                        afterLabel: function() { return null; }
                      }
                    }
                  },
                  scales: {
                    y: { beginAtZero: true, grid: { color: '#e5e5e5' }, ticks: { precision: 0 } },
                    x: { grid: { display: false } }
                  },
                  onClick: function(evt, elements) {
                    if (elements.length > 0) {
                      const index = elements[0].index;
                      const year = years[index];
                      const ids = activityIds.bySportAndYear[sport] && activityIds.bySportAndYear[sport][year] || [];
                      showActivityModal(formatSportName(sport) + ' - ' + year, getActivitiesFromIds(ids));
                    }
                  },
                  onHover: function(evt, elements) {
                    evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default';
                  }
                }
              });
            }

            function updateSportChart(sport) {
              if (sportCharts[sport]) {
                sportCharts[sport].destroy();
                sportCharts[sport] = null;
              }
              renderSportChart(sport);
            }

            function getSportColor(sport) {
              const colors = #{SPORT_COLORS.to_json};
              return colors[sport] || '#{DEFAULT_COLOR}';
            }

            function formatSportName(sport) {
              return sport.replace(/([a-z])([A-Z])/g, '$1 $2');
            }

            function getMetricLabel(metric) {
              const labels = {
                'total_activities': 'Total Activities',
                'total_days': 'Total Days',
                'total_time_hours': 'Total Hours',
                'total_distance_miles': 'Total Miles',
                'total_elevation_feet': 'Total Vertical (ft)',
                'total_calories': 'Total Calories'
              };
              return labels[metric] || metric;
            }

            // Chart.js configuration
            Chart.defaults.color = '#6d6d78';
            Chart.defaults.borderColor = '#e5e5e5';
            Chart.defaults.plugins.tooltip.displayColors = false;

            // By Year Chart
            const byYearCtx = document.getElementById('byYearChart').getContext('2d');
            new Chart(byYearCtx, {
              type: 'bar',
              data: #{by_year_chart.to_json},
              options: {
                responsive: true,
                plugins: {
                  legend: { display: false },
                  tooltip: {
                    callbacks: {
                      label: function(ctx) {
                        return 'Activities: ' + ctx.raw.toLocaleString();
                      }
                    }
                  }
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    grid: { color: '#e5e5e5' }
                  },
                  x: {
                    grid: { display: false }
                  }
                }
              }
            });

            // By Sport Chart
            const bySportCtx = document.getElementById('bySportChart').getContext('2d');
            new Chart(bySportCtx, {
              type: 'doughnut',
              data: #{by_sport_chart.to_json},
              options: {
                responsive: true,
                plugins: {
                  legend: {
                    position: 'right',
                    labels: { padding: 15 }
                  },
                  tooltip: {
                    callbacks: {
                      label: function(ctx) {
                        return ctx.label + ': ' + ctx.raw.toLocaleString() + ' activities';
                      }
                    }
                  }
                }
              }
            });

            // Winter Season Chart
            #{winter_chart_script(winter_season_chart)}

            // Dropdown switching for sport/year
            function showSportTab(sport) {
              document.querySelectorAll('.sport-tab-content').forEach(el => el.classList.remove('active'));
              document.getElementById('sport-' + sport).classList.add('active');
            }

            // Tab switching for winter sports
            function showWinterTab(sport) {
              // Hide all winter tables
              document.querySelectorAll('.winter-table').forEach(el => el.classList.add('hidden'));
              // Deactivate all winter tabs
              document.querySelectorAll('#winterTabs .tab').forEach(el => el.classList.remove('active'));

              // Show selected table
              document.getElementById('winter-' + sport).classList.remove('hidden');
              // Activate clicked tab
              event.target.classList.add('active');
            }

            // ===== Year Comparison =====
            let yearComparisonData = null;
            let yearComparisonChart = null;

            function initYearComparison() {
              const container = document.getElementById('year-comparison-container');
              if (!container) return;

              yearComparisonData = JSON.parse(container.dataset.comparisons || '{}');
              if (Object.keys(yearComparisonData).length === 0) return;

              // Get first sport
              const sportSelect = document.getElementById('yearComparisonSport');
              const sport = sportSelect.value;

              populateYearSelectors(sport);
              updateYearComparisonDisplay();
            }

            function populateYearSelectors(sport) {
              const data = yearComparisonData[sport];
              if (!data) return;

              const years = data.available_years;
              const year1Select = document.getElementById('yearComparisonYear1');
              const year2Select = document.getElementById('yearComparisonYear2');

              year1Select.innerHTML = years.map(y => `<option value="${y}">${y}</option>`).join('');
              year2Select.innerHTML = years.map(y => `<option value="${y}">${y}</option>`).join('');

              // Default: current year vs previous year
              if (years.length >= 2) {
                year1Select.value = years[0];
                year2Select.value = years[1];
              }
            }

            // Called when sport dropdown changes - repopulate years and update display
            function onYearSportChange() {
              const sport = document.getElementById('yearComparisonSport').value;
              populateYearSelectors(sport);
              updateYearComparisonDisplay();
            }

            // Called when year dropdowns change - just update display without repopulating
            function updateYearComparisonDisplay() {
              const sport = document.getElementById('yearComparisonSport').value;
              const year1 = document.getElementById('yearComparisonYear1').value;
              const year2 = document.getElementById('yearComparisonYear2').value;

              const data = yearComparisonData[sport];
              if (!data) return;

              const data1 = data.yearly_data[year1];
              const data2 = data.yearly_data[year2];

              if (!data1 || !data2) return;

              // Update labels
              document.getElementById('year-comparison-label1').textContent = year1;
              document.getElementById('year-comparison-label2').textContent = year2;

              // Update stats
              document.getElementById('year-comparison-stats1').innerHTML = formatComparisonStats(data1.stats);
              document.getElementById('year-comparison-stats2').innerHTML = formatComparisonStats(data2.stats);

              // Update changes
              const changes = calculateChanges(data1.stats, data2.stats);
              document.getElementById('year-comparison-changes').innerHTML = formatChangeIndicators(changes);

              // Update chart
              updateYearComparisonChart();
            }

            // Legacy function name for backwards compatibility
            function updateYearComparison() {
              updateYearComparisonDisplay();
            }

            function updateYearComparisonChart() {
              const sport = document.getElementById('yearComparisonSport').value;
              const year1 = document.getElementById('yearComparisonYear1').value;
              const year2 = document.getElementById('yearComparisonYear2').value;
              const metric = document.getElementById('year-comparison-metric').value;

              const data = yearComparisonData[sport];
              if (!data) return;

              // Use string keys since JSON converts integer keys to strings
              const data1 = data.yearly_data[year1];
              const data2 = data.yearly_data[year2];

              if (!data1 || !data2) return;

              const canvas = document.getElementById('year-comparison-chart');
              if (!canvas) return;

              if (yearComparisonChart) {
                yearComparisonChart.destroy();
              }

              const points1 = (data1.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
              const points2 = (data2.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));

              yearComparisonChart = new Chart(canvas.getContext('2d'), {
                type: 'line',
                data: {
                  datasets: [
                    {
                      label: year1,
                      data: points1,
                      borderColor: '#FC4C02',
                      backgroundColor: 'rgba(252, 76, 2, 0.1)',
                      fill: true,
                      tension: 0.3,
                      pointRadius: 2,
                      pointHoverRadius: 5
                    },
                    {
                      label: year2,
                      data: points2,
                      borderColor: '#6b7280',
                      backgroundColor: 'rgba(107, 114, 128, 0.1)',
                      fill: true,
                      tension: 0.3,
                      pointRadius: 2,
                      pointHoverRadius: 5,
                      borderDash: [5, 5]
                    }
                  ]
                },
                options: getComparisonChartOptions(metric, 'Day of Year', points1, points2, year1, year2)
              });
            }

            // ===== Season Comparison =====
            let seasonComparisonData = null;
            let seasonComparisonChart = null;

            function initSeasonComparison() {
              const container = document.getElementById('season-comparison-container');
              if (!container) return;

              seasonComparisonData = JSON.parse(container.dataset.comparisons || '{}');
              if (Object.keys(seasonComparisonData).length === 0) return;

              const sportSelect = document.getElementById('seasonComparisonSport');
              const sport = sportSelect.value;

              populateSeasonSelectors(sport);
              updateSeasonComparisonDisplay();
            }

            function populateSeasonSelectors(sport) {
              const data = seasonComparisonData[sport];
              if (!data) return;

              const seasons = data.available_seasons;
              const season1Select = document.getElementById('seasonComparisonSeason1');
              const season2Select = document.getElementById('seasonComparisonSeason2');

              season1Select.innerHTML = seasons.map(s => `<option value="${s}">${s}</option>`).join('');
              season2Select.innerHTML = seasons.map(s => `<option value="${s}">${s}</option>`).join('');

              // Default: current season vs previous season
              if (seasons.length >= 2) {
                season1Select.value = seasons[0];
                season2Select.value = seasons[1];
              }
            }

            // Called when sport dropdown changes - repopulate seasons and update display
            function onSeasonSportChange() {
              const sport = document.getElementById('seasonComparisonSport').value;
              populateSeasonSelectors(sport);
              updateSeasonComparisonDisplay();
            }

            // Called when season dropdowns change - just update display without repopulating
            function updateSeasonComparisonDisplay() {
              const sport = document.getElementById('seasonComparisonSport').value;
              const season1 = document.getElementById('seasonComparisonSeason1').value;
              const season2 = document.getElementById('seasonComparisonSeason2').value;

              const data = seasonComparisonData[sport];
              if (!data) return;

              const data1 = data.season_data[season1];
              const data2 = data.season_data[season2];

              if (!data1 || !data2) return;

              // Update labels
              document.getElementById('season-comparison-label1').textContent = season1 + ' Season';
              document.getElementById('season-comparison-label2').textContent = season2 + ' Season';

              // Update stats
              document.getElementById('season-comparison-stats1').innerHTML = formatComparisonStats(data1.stats);
              document.getElementById('season-comparison-stats2').innerHTML = formatComparisonStats(data2.stats);

              // Update changes
              const changes = calculateChanges(data1.stats, data2.stats);
              document.getElementById('season-comparison-changes').innerHTML = formatChangeIndicators(changes);

              // Update chart
              updateSeasonComparisonChart();
            }

            // Legacy function name for backwards compatibility
            function updateSeasonComparison() {
              updateSeasonComparisonDisplay();
            }

            function updateSeasonComparisonChart() {
              const sport = document.getElementById('seasonComparisonSport').value;
              const season1 = document.getElementById('seasonComparisonSeason1').value;
              const season2 = document.getElementById('seasonComparisonSeason2').value;
              const metric = document.getElementById('season-comparison-metric').value;

              const data = seasonComparisonData[sport];
              if (!data) return;

              const data1 = data.season_data[season1];
              const data2 = data.season_data[season2];

              if (!data1 || !data2) return;

              const canvas = document.getElementById('season-comparison-chart');
              if (!canvas) return;

              if (seasonComparisonChart) {
                seasonComparisonChart.destroy();
              }

              const points1 = (data1.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
              const points2 = (data2.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));

              seasonComparisonChart = new Chart(canvas.getContext('2d'), {
                type: 'line',
                data: {
                  datasets: [
                    {
                      label: season1,
                      data: points1,
                      borderColor: '#FC4C02',
                      backgroundColor: 'rgba(252, 76, 2, 0.1)',
                      fill: true,
                      tension: 0.3,
                      pointRadius: 2,
                      pointHoverRadius: 5
                    },
                    {
                      label: season2,
                      data: points2,
                      borderColor: '#6b7280',
                      backgroundColor: 'rgba(107, 114, 128, 0.1)',
                      fill: true,
                      tension: 0.3,
                      pointRadius: 2,
                      pointHoverRadius: 5,
                      borderDash: [5, 5]
                    }
                  ]
                },
                options: getComparisonChartOptions(metric, 'Day of Season (from Sep 1)', points1, points2, season1, season2)
              });
            }

            // ===== Shared Helper Functions =====
            function getComparisonChartOptions(metric, xAxisLabel, points1, points2, label1, label2) {
              const suffixes = { elevation: ' ft', miles: ' mi', hours: ' hrs', calories: ' cal' };
              const suffix = suffixes[metric] || '';

              // Helper to find cumulative value at or before a given day
              function getCumulativeAt(points, day) {
                let result = null;
                for (const p of points) {
                  if (p.x <= day) {
                    result = p;
                  } else {
                    break;
                  }
                }
                return result;
              }

              return {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'nearest', axis: 'x', intersect: false },
                plugins: {
                  legend: { position: 'top' },
                  tooltip: {
                    callbacks: {
                      title: ctx => {
                        const day = ctx[0].raw.x;
                        const p1 = getCumulativeAt(points1, day);
                        const p2 = getCumulativeAt(points2, day);
                        // Use date from whichever dataset has data at this day
                        return (p1 && p1.date) || (p2 && p2.date) || 'Day ' + day;
                      },
                      // Skip default label, we'll show everything in afterBody
                      label: () => null,
                      afterBody: ctx => {
                        const day = ctx[0].raw.x;
                        const p1 = getCumulativeAt(points1, day);
                        const p2 = getCumulativeAt(points2, day);

                        const val1 = p1 ? p1.y.toLocaleString() : '0';
                        const val2 = p2 ? p2.y.toLocaleString() : '0';

                        return [
                          label1 + ': ' + val1 + suffix,
                          label2 + ': ' + val2 + suffix
                        ];
                      }
                    },
                    // Filter out the null labels
                    filter: (item) => item.text !== null
                  }
                },
                scales: {
                  x: {
                    type: 'linear',
                    min: 1,
                    max: xAxisLabel.includes('Season') ? 365 : 366,
                    title: { display: false },
                    grid: { color: '#e5e5e5' },
                    ticks: {
                      autoSkip: false,
                      maxRotation: 0,
                      callback: function(value) {
                        // Day of year for start of each month (non-leap year)
                        const yearMonthStarts = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
                        const yearMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                        // Season starts Sep 1 (day 0 of season = Sep 1)
                        const seasonMonthStarts = [1, 31, 62, 92, 123, 153, 184, 214, 245, 275, 306, 336];
                        const seasonMonths = ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];

                        if (xAxisLabel.includes('Season')) {
                          const idx = seasonMonthStarts.indexOf(value);
                          return idx >= 0 ? seasonMonths[idx] : '';
                        } else {
                          const idx = yearMonthStarts.indexOf(value);
                          return idx >= 0 ? yearMonths[idx] : '';
                        }
                      }
                    },
                    afterBuildTicks: function(axis) {
                      // Set ticks to month start days
                      if (xAxisLabel.includes('Season')) {
                        axis.ticks = [1, 31, 62, 92, 123, 153, 184, 214, 245, 275, 306, 336].map(v => ({value: v}));
                      } else {
                        axis.ticks = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335].map(v => ({value: v}));
                      }
                    }
                  },
                  y: { beginAtZero: true, title: { display: true, text: getMetricLabel(metric) }, grid: { color: '#e5e5e5' } }
                }
              };
            }

            function getMetricLabel(metric) {
              const labels = {
                activities: 'Cumulative Activities',
                hours: 'Cumulative Hours',
                miles: 'Cumulative Miles',
                elevation: 'Cumulative Vertical (ft)',
                calories: 'Cumulative Calories'
              };
              return labels[metric] || metric;
            }

            function formatComparisonStats(stats) {
              return `
                <div class="comparison-stat"><span class="comparison-stat-label">Activities</span><span class="comparison-stat-value">${formatNumber(stats.total_activities)}</span></div>
                <div class="comparison-stat"><span class="comparison-stat-label">Days</span><span class="comparison-stat-value">${formatNumber(stats.total_days)}</span></div>
                <div class="comparison-stat"><span class="comparison-stat-label">Hours</span><span class="comparison-stat-value">${formatNumber(stats.total_time_hours)}</span></div>
                <div class="comparison-stat"><span class="comparison-stat-label">Miles</span><span class="comparison-stat-value">${formatNumber(stats.total_distance_miles)}</span></div>
                <div class="comparison-stat"><span class="comparison-stat-label">Vertical (ft)</span><span class="comparison-stat-value">${formatNumber(stats.total_elevation_feet)}</span></div>
                <div class="comparison-stat"><span class="comparison-stat-label">Calories</span><span class="comparison-stat-value">${formatNumber(stats.total_calories)}</span></div>
              `;
            }

            function calculateChanges(current, previous) {
              const keys = ['total_activities', 'total_days', 'total_time_hours', 'total_distance_miles', 'total_elevation_feet', 'total_calories'];
              const changes = {};
              keys.forEach(key => {
                const curr = current[key] || 0;
                const prev = previous[key] || 0;
                const diff = curr - prev;
                const pct = prev === 0 ? (curr === 0 ? 0 : 100) : Math.round((diff / prev) * 100);
                changes[key] = { diff, pct };
              });
              return changes;
            }

            function formatChangeIndicators(changes) {
              const keys = ['total_activities', 'total_days', 'total_time_hours', 'total_distance_miles', 'total_elevation_feet', 'total_calories'];
              return '<div class="change-indicators">' + keys.map(key => {
                const change = changes[key];
                const cssClass = change.pct > 0 ? 'change-positive' : change.pct < 0 ? 'change-negative' : 'change-neutral';
                const arrow = change.pct > 0 ? '↑' : change.pct < 0 ? '↓' : '−';
                const diffSign = change.diff > 0 ? '+' : '';
                const diffVal = Math.abs(change.diff) >= 1000 ? change.diff.toLocaleString() : (Number.isInteger(change.diff) ? change.diff : change.diff.toFixed(1));
                return `<div class="change-indicator ${cssClass}">${arrow}${Math.abs(change.pct)}% (${diffSign}${diffVal})</div>`;
              }).join('') + '</div>';
            }

            function formatNumber(num) {
              if (num === null || num === undefined) return '0';
              return num.toLocaleString();
            }

            // Initialize comparisons on page load
            document.addEventListener('DOMContentLoaded', function() {
              initYearComparison();
              initSeasonComparison();
            });

            // Activity Modal Functions
            function showActivityModal(title, activities) {
              document.getElementById('modalTitle').textContent = title;
              const list = document.getElementById('activityList');

              // Sort activities by date (newest first)
              activities.sort((a, b) => b.date.localeCompare(a.date));

              list.innerHTML = activities.map(a => `
                <a href="https://www.strava.com/activities/${a.id}" target="_blank" class="activity-item">
                  <div class="activity-info">
                    <span class="activity-name">${a.name}</span>
                    <span class="activity-date">${formatActivityDate(a.date)}</span>
                    <span class="strava-link">View on Strava &rarr;</span>
                  </div>
                  <div class="activity-stats">
                    <span>${a.hours.toFixed(1)} hrs</span>
                    <span>${a.miles.toFixed(1)} mi</span>
                    <span>${formatNumber(a.elevation)} ft</span>
                    <span>${formatNumber(a.calories)} cal</span>
                  </div>
                </a>
              `).join('');

              document.getElementById('activityModal').classList.add('active');
            }

            function closeActivityModal() {
              document.getElementById('activityModal').classList.remove('active');
            }

            function formatActivityDate(dateStr) {
              const date = new Date(dateStr);
              return date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
            }

            // Close modal on Escape key
            document.addEventListener('keydown', function(e) {
              if (e.key === 'Escape') closeActivityModal();
            });

            // Year comparison click handlers
            function showYearComparisonActivities(cardNum) {
              const sport = document.getElementById('yearComparisonSport').value;
              const year = cardNum === 1
                ? document.getElementById('yearComparisonYear1').value
                : document.getElementById('yearComparisonYear2').value;
              const ids = activityIds.bySportAndYear[sport] && activityIds.bySportAndYear[sport][year] || [];
              const sportName = document.getElementById('yearComparisonSport').options[document.getElementById('yearComparisonSport').selectedIndex].text;
              showActivityModal(sportName + ' - ' + year, getActivitiesFromIds(ids));
            }

            // Season comparison click handlers
            function showSeasonComparisonActivities(cardNum) {
              const sport = document.getElementById('seasonComparisonSport').value;
              const season = cardNum === 1
                ? document.getElementById('seasonComparisonSeason1').value
                : document.getElementById('seasonComparisonSeason2').value;
              const ids = activityIds.winterBySeason[season] && activityIds.winterBySeason[season].by_sport[sport] || [];
              const sportName = document.getElementById('seasonComparisonSport').options[document.getElementById('seasonComparisonSport').selectedIndex].text;
              showActivityModal(sportName + ' - ' + season, getActivitiesFromIds(ids));
            }

            // Table sorting
            document.querySelectorAll('table.sortable').forEach(table => {
              const headers = table.querySelectorAll('th');
              const tbody = table.querySelector('tbody');

              headers.forEach((header, columnIndex) => {
                header.addEventListener('click', () => {
                  // Get only data rows, not chart rows
                  const allRows = Array.from(tbody.querySelectorAll('tr'));
                  const dataRows = allRows.filter(r => !r.classList.contains('sport-chart-row'));
                  const isAscending = header.classList.contains('sort-asc');

                  // Clear all sort classes
                  headers.forEach(h => h.classList.remove('sort-asc', 'sort-desc'));

                  // Sort data rows
                  dataRows.sort((a, b) => {
                    const aCell = a.cells[columnIndex];
                    const bCell = b.cells[columnIndex];
                    if (!aCell || !bCell) return 0;

                    // Get sort value from data attribute or text content
                    let aVal = aCell.dataset.sort !== undefined ? aCell.dataset.sort : aCell.textContent.trim();
                    let bVal = bCell.dataset.sort !== undefined ? bCell.dataset.sort : bCell.textContent.trim();

                    // Try to parse as numbers (remove commas)
                    const aNum = parseFloat(aVal.replace(/,/g, ''));
                    const bNum = parseFloat(bVal.replace(/,/g, ''));

                    if (!isNaN(aNum) && !isNaN(bNum)) {
                      return isAscending ? aNum - bNum : bNum - aNum;
                    }

                    // String comparison
                    return isAscending
                      ? aVal.localeCompare(bVal)
                      : bVal.localeCompare(aVal);
                  });

                  // Update sort indicator
                  header.classList.add(isAscending ? 'sort-desc' : 'sort-asc');

                  // Re-append sorted rows, keeping chart rows with their data rows
                  dataRows.forEach(row => {
                    tbody.appendChild(row);
                    // Find and append the associated chart row if it exists
                    const chartRowId = row.id ? row.id.replace('sport-row-', 'sport-chart-row-') : null;
                    const chartRow = chartRowId ? document.getElementById(chartRowId) : null;
                    if (chartRow) tbody.appendChild(chartRow);
                  });
                });
              });
            });
          </script>
        </body>
        </html>
      HTML
    end

    def sport_row(sport, stats)
      color = SPORT_COLORS[sport] || DEFAULT_COLOR
      cal_per_hour = stats[:total_time_hours] > 0 ? (stats[:total_calories] / stats[:total_time_hours]).round(0) : 0
      cal_per_activity = stats[:total_activities] > 0 ? (stats[:total_calories] / stats[:total_activities]).round(0) : 0
      <<~HTML
        <tr class="clickable" id="sport-row-#{sport}" onclick="toggleSportChart('#{sport}')">
          <td data-sort="#{format_sport_name(sport)}"><span class="sport-badge" style="background: #{color}">#{format_sport_name(sport)}</span><span class="expand-indicator"></span></td>
          <td class="number" data-sort="#{stats[:total_activities]}">#{format_number(stats[:total_activities])}</td>
          <td class="number" data-sort="#{stats[:total_days]}">#{format_number(stats[:total_days])}</td>
          <td class="number" data-sort="#{stats[:total_time_hours]}">#{format_number(stats[:total_time_hours])}</td>
          <td class="number" data-sort="#{stats[:total_distance_miles]}">#{format_number(stats[:total_distance_miles])}</td>
          <td class="number" data-sort="#{stats[:total_elevation_feet]}">#{format_number(stats[:total_elevation_feet])}</td>
          <td class="number" data-sort="#{stats[:total_calories]}">#{format_number(stats[:total_calories])}</td>
          <td class="number" data-sort="#{cal_per_hour}">#{format_number(cal_per_hour)}</td>
          <td class="number" data-sort="#{cal_per_activity}">#{format_number(cal_per_activity)}</td>
        </tr>
        <tr class="sport-chart-row" id="sport-chart-row-#{sport}">
          <td colspan="9">
            <div class="sport-chart-container">
              <div class="sport-chart-header">
                <span class="sport-chart-title">#{format_sport_name(sport)} by Year</span>
                <select id="sport-chart-metric-#{sport}" onchange="updateSportChart('#{sport}')">
                  <option value="total_activities" selected>Activities</option>
                  <option value="total_days">Days</option>
                  <option value="total_time_hours">Hours</option>
                  <option value="total_distance_miles">Miles</option>
                  <option value="total_elevation_feet">Vertical (ft)</option>
                  <option value="total_calories">Calories</option>
                </select>
              </div>
              <div style="height: 200px;">
                <canvas id="sport-chart-#{sport}"></canvas>
              </div>
            </div>
          </td>
        </tr>
      HTML
    end

    def year_row(year, stats, sport: nil)
      if sport
        onclick = "showActivityModal('#{format_sport_name(sport)} - #{year}', getActivitiesFromIds(activityIds.bySportAndYear['#{sport}'] && activityIds.bySportAndYear['#{sport}']['#{year}'] || []))"
      else
        onclick = "showActivityModal('#{year}', getActivitiesFromIds(activityIds.byYear['#{year}'] || []))"
      end
      <<~HTML
        <tr class="clickable" onclick="#{onclick}">
          <td data-sort="#{year}"><strong>#{year}</strong></td>
          <td class="number" data-sort="#{stats[:total_activities]}">#{format_number(stats[:total_activities])}</td>
          <td class="number" data-sort="#{stats[:total_days]}">#{format_number(stats[:total_days])}</td>
          <td class="number" data-sort="#{stats[:total_time_hours]}">#{format_number(stats[:total_time_hours])}</td>
          <td class="number" data-sort="#{stats[:total_distance_miles]}">#{format_number(stats[:total_distance_miles])}</td>
          <td class="number" data-sort="#{stats[:total_elevation_feet]}">#{format_number(stats[:total_elevation_feet])}</td>
          <td class="number" data-sort="#{stats[:total_calories]}">#{format_number(stats[:total_calories])}</td>
        </tr>
      HTML
    end

    def all_years_tab(by_year)
      <<~HTML
        <div id="sport-All" class="tab-content sport-tab-content active">
          <table class="sortable">
            <thead>
              <tr>
                <th>Year</th>
                <th class="number">Activities</th>
                <th class="number">Days</th>
                <th class="number">Hours</th>
                <th class="number">Miles</th>
                <th class="number">Vertical (ft)</th>
                <th class="number">Calories</th>
              </tr>
            </thead>
            <tbody>
              #{by_year.map { |year, s| year_row(year, s) }.join("\n")}
            </tbody>
          </table>
        </div>
      HTML
    end

    def sport_year_tab(sport, years, is_active)
      <<~HTML
        <div id="sport-#{sport}" class="tab-content sport-tab-content#{is_active ? ' active' : ''}">
          <table class="sortable">
            <thead>
              <tr>
                <th>Year</th>
                <th class="number">Activities</th>
                <th class="number">Days</th>
                <th class="number">Hours</th>
                <th class="number">Miles</th>
                <th class="number">Vertical (ft)</th>
                <th class="number">Calories</th>
              </tr>
            </thead>
            <tbody>
              #{years.map { |year, s| year_row(year, s, sport: sport) }.join("\n")}
            </tbody>
          </table>
        </div>
      HTML
    end

    def winter_section(winter_by_season)
      return '' if winter_by_season.empty?

      # Collect all sports that appear in winter data
      all_sports = winter_by_season.values.flat_map { |d| d[:by_sport].keys }.uniq.sort

      # Build tabs and tables for each sport
      sport_tabs = all_sports.map { |sport| "<button class=\"tab\" onclick=\"showWinterTab('#{sport}')\">#{format_sport_name(sport)}</button>" }.join("\n")

      # Build table for "All" (totals)
      all_table = winter_stats_table('winter-all', winter_by_season.map { |season, data| season_row(season, data[:totals]) }.join("\n"))

      # Build table for each sport
      sport_tables = all_sports.map do |sport|
        rows = winter_by_season.map do |season, data|
          stats = data[:by_sport][sport]
          stats ? season_row(season, stats, sport: sport) : nil
        end.compact.join("\n")

        winter_stats_table("winter-#{sport}", rows, hidden: true)
      end.join("\n")

      <<~HTML
        <div class="section">
          <h2>Winter Sports by Season</h2>
          <p class="subtitle" style="margin-bottom: 1rem; color: var(--text-secondary);">Seasons run September through August</p>
          <div class="chart-container">
            <canvas id="winterSeasonChart"></canvas>
          </div>
          <div class="tabs" id="winterTabs">
            <button class="tab active" onclick="showWinterTab('all')">All</button>
            #{sport_tabs}
          </div>
          #{all_table}
          #{sport_tables}
        </div>
      HTML
    end

    def winter_stats_table(id, rows, hidden: false)
      <<~HTML
        <table id="#{id}" class="sortable winter-table#{hidden ? ' hidden' : ''}">
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
          <tbody>
            #{rows}
          </tbody>
        </table>
      HTML
    end

    def year_comparison_section(year_comparisons)
      return '' if year_comparisons.empty?

      sports = year_comparisons.keys
      first_sport = sports.first
      first_data = year_comparisons[first_sport]

      sport_options = sports.map do |sport|
        "<option value=\"#{sport}\">#{format_sport_name(sport)}</option>"
      end.join("\n")

      # Store all the data as JSON for JavaScript to use (exclude activities array from stats)
      comparison_data = year_comparisons.transform_values do |data|
        {
          available_years: data[:available_years],
          current_year: data[:current_year],
          current_day: data[:current_day],
          yearly_data: data[:yearly_data].transform_values do |yd|
            {
              stats: yd[:stats].reject { |k, _| k == :activities },
              cumulative_clipped: yd[:cumulative_clipped]
            }
          end
        }
      end

      <<~HTML
        <div class="section">
          <h2>Year-over-Year Comparison</h2>
          <div class="comparison-selectors">
            <div class="sport-selector">
              <label>Sport:</label>
              <select id="yearComparisonSport" onchange="onYearSportChange()">
                #{sport_options}
              </select>
            </div>
            <div class="year-selectors">
              <label>Compare:</label>
              <select id="yearComparisonYear1" onchange="updateYearComparisonDisplay()"></select>
              <span>vs</span>
              <select id="yearComparisonYear2" onchange="updateYearComparisonDisplay()"></select>
            </div>
          </div>
          <div id="year-comparison-container" class="comparison-container"
               data-comparisons='#{comparison_data.to_json}'>
            <div class="comparison-grid">
              <div class="comparison-card current clickable" id="year-comparison-card1" onclick="showYearComparisonActivities(1)">
                <h4 id="year-comparison-label1"></h4>
                <div id="year-comparison-stats1"></div>
              </div>
              <div class="comparison-vs">
                <div class="comparison-vs-header">vs</div>
                <div id="year-comparison-changes"></div>
              </div>
              <div class="comparison-card clickable" id="year-comparison-card2" onclick="showYearComparisonActivities(2)">
                <h4 id="year-comparison-label2"></h4>
                <div id="year-comparison-stats2"></div>
              </div>
            </div>
            <div class="comparison-chart-section">
              <div class="chart-controls">
                <label>Show: </label>
                <select id="year-comparison-metric" onchange="updateYearComparisonChart()">
                  <option value="activities" selected>Activities</option>
                  <option value="hours">Hours</option>
                  <option value="miles">Miles</option>
                  <option value="elevation">Vertical (ft)</option>
                  <option value="calories">Calories</option>
                </select>
              </div>
              <div class="chart-container" style="height: 200px;">
                <canvas id="year-comparison-chart"></canvas>
              </div>
            </div>
          </div>
        </div>
      HTML
    end

    def season_comparison_section(season_comparisons)
      return '' if season_comparisons.empty?

      sports = season_comparisons.keys

      sport_options = sports.map do |sport|
        "<option value=\"#{sport}\">#{format_sport_name(sport)}</option>"
      end.join("\n")

      # Store all the data as JSON for JavaScript to use (exclude activities array from stats)
      comparison_data = season_comparisons.transform_values do |data|
        {
          available_seasons: data[:available_seasons],
          current_season: data[:current_season],
          current_day: data[:current_day],
          season_data: data[:season_data].transform_values do |sd|
            {
              stats: sd[:stats].reject { |k, _| k == :activities },
              cumulative_clipped: sd[:cumulative_clipped]
            }
          end
        }
      end

      <<~HTML
        <div class="section">
          <h2>Winter Season Comparison</h2>
          <p class="subtitle" style="margin-bottom: 1rem; color: var(--text-secondary);">Compare your progress this season vs last season (seasons run Sep-Aug)</p>
          <div class="comparison-selectors">
            <div class="sport-selector">
              <label>Sport:</label>
              <select id="seasonComparisonSport" onchange="onSeasonSportChange()">
                #{sport_options}
              </select>
            </div>
            <div class="year-selectors">
              <label>Compare:</label>
              <select id="seasonComparisonSeason1" onchange="updateSeasonComparisonDisplay()"></select>
              <span>vs</span>
              <select id="seasonComparisonSeason2" onchange="updateSeasonComparisonDisplay()"></select>
            </div>
          </div>
          <div id="season-comparison-container" class="comparison-container"
               data-comparisons='#{comparison_data.to_json}'>
            <div class="comparison-grid">
              <div class="comparison-card current clickable" id="season-comparison-card1" onclick="showSeasonComparisonActivities(1)">
                <h4 id="season-comparison-label1"></h4>
                <div id="season-comparison-stats1"></div>
              </div>
              <div class="comparison-vs">
                <div class="comparison-vs-header">vs</div>
                <div id="season-comparison-changes"></div>
              </div>
              <div class="comparison-card clickable" id="season-comparison-card2" onclick="showSeasonComparisonActivities(2)">
                <h4 id="season-comparison-label2"></h4>
                <div id="season-comparison-stats2"></div>
              </div>
            </div>
            <div class="comparison-chart-section">
              <div class="chart-controls">
                <label>Show: </label>
                <select id="season-comparison-metric" onchange="updateSeasonComparisonChart()">
                  <option value="activities" selected>Activities</option>
                  <option value="hours">Hours</option>
                  <option value="miles">Miles</option>
                  <option value="elevation">Vertical (ft)</option>
                  <option value="calories">Calories</option>
                </select>
              </div>
              <div class="chart-container" style="height: 200px;">
                <canvas id="season-comparison-chart"></canvas>
              </div>
            </div>
          </div>
        </div>
      HTML
    end

    def comparison_card_with_chart(id, current_label, previous_label, current_stats, previous_stats, changes, current_cumulative, previous_cumulative, hidden: false)
      chart_id = "#{id}-chart"
      metric_select_id = "#{id}-metric"

      <<~HTML
        <div id="#{id}" class="comparison-container#{hidden ? ' hidden' : ''}"
             data-current-label="#{current_label}"
             data-previous-label="#{previous_label}"
             data-current-cumulative='#{current_cumulative.to_json}'
             data-previous-cumulative='#{previous_cumulative.to_json}'>
          <div class="comparison-grid">
            <div class="comparison-card current">
              <h4>#{current_label}</h4>
              #{comparison_stats(current_stats)}
            </div>
            <div class="comparison-vs">
              <div class="comparison-vs-header">vs</div>
              #{change_indicators(changes)}
            </div>
            <div class="comparison-card">
              <h4>#{previous_label}</h4>
              #{comparison_stats(previous_stats)}
            </div>
          </div>
          <div class="comparison-chart-section">
            <div class="chart-controls">
              <label>Show: </label>
              <select class="metric-selector" onchange="updateComparisonChart('#{id}', this.value)">
                <option value="activities" selected>Activities</option>
                <option value="hours">Hours</option>
                <option value="miles">Miles</option>
                <option value="elevation">Vertical (ft)</option>
                <option value="calories">Calories</option>
              </select>
            </div>
            <div class="chart-container" style="height: 200px;">
              <canvas id="#{id}-chart"></canvas>
            </div>
          </div>
        </div>
      HTML
    end

    def comparison_stats(stats)
      <<~HTML
        <div class="comparison-stat">
          <span class="comparison-stat-label">Activities</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_activities])}</span>
        </div>
        <div class="comparison-stat">
          <span class="comparison-stat-label">Days</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_days])}</span>
        </div>
        <div class="comparison-stat">
          <span class="comparison-stat-label">Hours</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_time_hours])}</span>
        </div>
        <div class="comparison-stat">
          <span class="comparison-stat-label">Miles</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_distance_miles])}</span>
        </div>
        <div class="comparison-stat">
          <span class="comparison-stat-label">Vertical (ft)</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_elevation_feet])}</span>
        </div>
        <div class="comparison-stat">
          <span class="comparison-stat-label">Calories</span>
          <span class="comparison-stat-value">#{format_number(stats[:total_calories])}</span>
        </div>
      HTML
    end

    def change_indicators(changes)
      indicators = %i[total_activities total_days total_time_hours total_distance_miles total_elevation_feet total_calories].map do |key|
        change = changes[key]
        css_class = if change[:pct] > 0
                      'change-positive'
                    elsif change[:pct] < 0
                      'change-negative'
                    else
                      'change-neutral'
                    end

        arrow = if change[:pct] > 0
                  '↑'
                elsif change[:pct] < 0
                  '↓'
                else
                  '−'
                end

        pct_display = change[:pct].abs
        diff = change[:diff]
        diff_sign = diff > 0 ? '+' : ''
        diff_display = diff.is_a?(Float) ? diff.round(1) : diff
        "<div class=\"change-indicator #{css_class}\">#{arrow}#{pct_display}% (#{diff_sign}#{format_number(diff_display)})</div>"
      end

      "<div class=\"change-indicators\">#{indicators.join("\n")}</div>"
    end

    def season_row(season, stats, sport: nil)
      # Extract year for sorting (e.g., "2023-24" -> 2023)
      sort_year = season.to_s.split('-').first.to_i
      if sport
        onclick = "showActivityModal('#{format_sport_name(sport)} - #{season}', getActivitiesFromIds(activityIds.winterBySeason['#{season}'] && activityIds.winterBySeason['#{season}'].by_sport['#{sport}'] || []))"
        title = "#{format_sport_name(sport)} - #{season}"
      else
        onclick = "showActivityModal('Winter #{season}', getActivitiesFromIds(activityIds.winterBySeason['#{season}'] && activityIds.winterBySeason['#{season}'].totals || []))"
        title = "Winter #{season}"
      end
      <<~HTML
        <tr class="clickable" onclick="#{onclick}">
          <td data-sort="#{sort_year}"><strong>#{season}</strong></td>
          <td class="number" data-sort="#{stats[:total_activities]}">#{format_number(stats[:total_activities])}</td>
          <td class="number" data-sort="#{stats[:total_days]}">#{format_number(stats[:total_days])}</td>
          <td class="number" data-sort="#{stats[:total_time_hours]}">#{format_number(stats[:total_time_hours])}</td>
          <td class="number" data-sort="#{stats[:total_distance_miles]}">#{format_number(stats[:total_distance_miles])}</td>
          <td class="number" data-sort="#{stats[:total_elevation_feet]}">#{format_number(stats[:total_elevation_feet])}</td>
          <td class="number" data-sort="#{stats[:total_calories]}">#{format_number(stats[:total_calories])}</td>
        </tr>
      HTML
    end

    def resorts_section(resorts_by_season)
      return '' if resorts_by_season.empty?

      # Prepare chart data for each season, storing only activity IDs
      chart_data = resorts_by_season.transform_values do |resorts|
        sorted = resorts.sort_by { |_, data| -data[:stats][:total_days] }
        {
          labels: sorted.map { |name, data| "#{name} (#{data[:stats][:total_days]}d)" },
          names: sorted.map { |name, _| name },
          days: sorted.map { |_, data| data[:stats][:total_days] },
          vertical: sorted.map { |_, data| data[:stats][:total_elevation_feet].to_i },
          activityIds: sorted.map { |_, data| data[:activities].map { |a| a['id'] } }
        }
      end

      <<~HTML
        <div class="section">
          <h2>Ski Resorts by Season</h2>
          <div class="chart-tabs">
            <div class="tabs" id="resortTabs">
              #{resorts_by_season.keys.reverse.map.with_index { |season, i| "<button class=\"tab#{i == 0 ? ' active' : ''}\" onclick=\"showResortSeason('#{season}')\">#{season}</button>" }.join("\n")}
            </div>
            <div class="chart-metric-selector">
              <label>Show:</label>
              <select id="resortMetric" onchange="updateResortChart()">
                <option value="days">Days</option>
                <option value="vertical">Vertical (ft)</option>
              </select>
            </div>
          </div>
          <div class="chart-container" style="height: 250px;">
            <canvas id="resortChart"></canvas>
          </div>
          <script>
            var resortChartData = #{chart_data.to_json};
            var currentResortSeason = '#{resorts_by_season.keys.last}';
            var resortChart = null;

            function showResortSeason(season) {
              currentResortSeason = season;
              document.querySelectorAll('#resortTabs .tab').forEach(t => t.classList.remove('active'));
              event.target.classList.add('active');
              updateResortChart();
            }

            function updateResortChart() {
              const data = resortChartData[currentResortSeason];
              const metric = document.getElementById('resortMetric').value;
              const values = metric === 'days' ? data.days : data.vertical;
              const label = metric === 'days' ? 'Days' : 'Vertical (ft)';

              if (resortChart) resortChart.destroy();

              resortChart = new Chart(document.getElementById('resortChart').getContext('2d'), {
                type: 'bar',
                data: {
                  labels: data.labels,
                  datasets: [{
                    label: label,
                    data: values,
                    backgroundColor: '#E91E63'
                  }]
                },
                options: {
                  indexAxis: 'y',
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: { legend: { display: false } },
                  scales: {
                    x: { beginAtZero: true, grid: { color: '#e5e5e5' }, ticks: { precision: 0 } },
                    y: { grid: { display: false } }
                  },
                  onClick: function(evt, elements) {
                    if (elements.length > 0) {
                      const index = elements[0].index;
                      const resortName = data.names[index];
                      const ids = data.activityIds[index];
                      showActivityModal(resortName + ' - ' + currentResortSeason, getActivitiesFromIds(ids));
                    }
                  },
                  onHover: function(evt, elements) {
                    evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default';
                  }
                }
              });
            }

            document.addEventListener('DOMContentLoaded', updateResortChart);
          </script>
        </div>
      HTML
    end

    def backcountry_section(backcountry_by_season)
      return '' if backcountry_by_season.empty?

      # Prepare chart data for each season
      chart_data = backcountry_by_season.transform_values do |regions|
        sorted = regions.sort_by { |_, data| -data[:stats][:total_days] }
        {
          labels: sorted.map { |name, data| "#{name} (#{data[:stats][:total_days]}d)" },
          days: sorted.map { |_, data| data[:stats][:total_days] },
          vertical: sorted.map { |_, data| data[:stats][:total_elevation_feet].to_i }
        }
      end

      <<~HTML
        <div class="section">
          <h2>Backcountry Skiing by Season</h2>
          <div class="chart-tabs">
            <div class="tabs" id="bcTabs">
              #{backcountry_by_season.keys.reverse.map.with_index { |season, i| "<button class=\"tab#{i == 0 ? ' active' : ''}\" onclick=\"showBCSeason('#{season}')\">#{season}</button>" }.join("\n")}
            </div>
            <div class="chart-metric-selector">
              <label>Show:</label>
              <select id="bcMetric" onchange="updateBCChart()">
                <option value="days">Days</option>
                <option value="vertical">Vertical (ft)</option>
              </select>
            </div>
          </div>
          <div class="chart-container" style="height: 250px;">
            <canvas id="bcChart"></canvas>
          </div>
          <script>
            var bcChartData = #{chart_data.to_json};
            var currentBCSeason = '#{backcountry_by_season.keys.last}';
            var bcChart = null;

            function showBCSeason(season) {
              currentBCSeason = season;
              document.querySelectorAll('#bcTabs .tab').forEach(t => t.classList.remove('active'));
              event.target.classList.add('active');
              updateBCChart();
            }

            function updateBCChart() {
              const data = bcChartData[currentBCSeason];
              const metric = document.getElementById('bcMetric').value;
              const values = metric === 'days' ? data.days : data.vertical;
              const label = metric === 'days' ? 'Days' : 'Vertical (ft)';

              if (bcChart) bcChart.destroy();

              bcChart = new Chart(document.getElementById('bcChart').getContext('2d'), {
                type: 'bar',
                data: {
                  labels: data.labels,
                  datasets: [{
                    label: label,
                    data: values,
                    backgroundColor: '#FF5722'
                  }]
                },
                options: {
                  indexAxis: 'y',
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: { legend: { display: false } },
                  scales: {
                    x: { beginAtZero: true, grid: { color: '#e5e5e5' }, ticks: { precision: 0 } },
                    y: { grid: { display: false } }
                  }
                }
              });
            }

            document.addEventListener('DOMContentLoaded', updateBCChart);
          </script>
        </div>
      HTML
    end

    def peaks_section(peaks_by_season)
      return '' if peaks_by_season.nil? || peaks_by_season.empty?

      # Prepare chart data for each season, storing only activity IDs
      chart_data = peaks_by_season.transform_values do |peaks|
        sorted = peaks.sort_by { |_, data| -data[:stats][:total_days] }
        {
          labels: sorted.map { |name, data| "#{name} (#{data[:stats][:total_days]}d)" },
          names: sorted.map { |name, _| name },
          days: sorted.map { |_, data| data[:stats][:total_days] },
          vertical: sorted.map { |_, data| data[:stats][:total_elevation_feet].to_i },
          activityIds: sorted.map { |_, data| data[:activities].map { |a| a['id'] } }
        }
      end

      <<~HTML
        <div class="section">
          <h2>Backcountry Mountain Peaks by Season</h2>
          <div class="chart-tabs">
            <div class="tabs" id="peakTabs">
              #{peaks_by_season.keys.reverse.map.with_index { |season, i| "<button class=\"tab#{i == 0 ? ' active' : ''}\" onclick=\"showPeakSeason('#{season}')\">#{season}</button>" }.join("\n")}
            </div>
            <div class="chart-metric-selector">
              <label>Show:</label>
              <select id="peakMetric" onchange="updatePeakChart()">
                <option value="days">Days</option>
                <option value="vertical">Vertical (ft)</option>
              </select>
            </div>
          </div>
          <div class="chart-container" style="height: 300px;">
            <canvas id="peakChart"></canvas>
          </div>
          <script>
            var peakChartData = #{chart_data.to_json};
            var currentPeakSeason = '#{peaks_by_season.keys.last}';
            var peakChart = null;

            function showPeakSeason(season) {
              currentPeakSeason = season;
              document.querySelectorAll('#peakTabs .tab').forEach(t => t.classList.remove('active'));
              event.target.classList.add('active');
              updatePeakChart();
            }

            function updatePeakChart() {
              const data = peakChartData[currentPeakSeason];
              const metric = document.getElementById('peakMetric').value;
              const values = metric === 'days' ? data.days : data.vertical;
              const label = metric === 'days' ? 'Days' : 'Vertical (ft)';

              if (peakChart) peakChart.destroy();

              peakChart = new Chart(document.getElementById('peakChart').getContext('2d'), {
                type: 'bar',
                data: {
                  labels: data.labels,
                  datasets: [{
                    label: label,
                    data: values,
                    backgroundColor: '#9C27B0'
                  }]
                },
                options: {
                  indexAxis: 'y',
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: { legend: { display: false } },
                  scales: {
                    x: { beginAtZero: true, grid: { color: '#e5e5e5' }, ticks: { precision: 0 } },
                    y: { grid: { display: false } }
                  },
                  onClick: function(evt, elements) {
                    if (elements.length > 0) {
                      const index = elements[0].index;
                      const peakName = data.names[index];
                      const ids = data.activityIds[index];
                      showActivityModal(peakName + ' - ' + currentPeakSeason, getActivitiesFromIds(ids));
                    }
                  },
                  onHover: function(evt, elements) {
                    evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default';
                  }
                }
              });
            }

            document.addEventListener('DOMContentLoaded', updatePeakChart);
          </script>
        </div>
      HTML
    end

    def prepare_by_year_chart(by_year)
      {
        labels: by_year.keys,
        datasets: [{
          label: 'Activities',
          data: by_year.values.map { |s| s[:total_activities] },
          backgroundColor: '#FC4C02'
        }]
      }
    end

    def prepare_by_sport_chart(by_sport)
      sorted = by_sport.sort_by { |_, s| -s[:total_activities] }.first(10)

      {
        labels: sorted.map { |sport, _| format_sport_name(sport) },
        datasets: [{
          data: sorted.map { |_, s| s[:total_activities] },
          backgroundColor: sorted.map { |sport, _| SPORT_COLORS[sport] || DEFAULT_COLOR }
        }]
      }
    end

    def prepare_sport_by_year_charts(by_sport_and_year)
      by_sport_and_year.transform_values do |years|
        {
          labels: years.keys,
          data: years.values.map { |s| s[:total_activities] }
        }
      end
    end

    def prepare_winter_season_chart(winter_by_season)
      return nil if winter_by_season.empty?

      seasons = winter_by_season.keys
      sports = winter_by_season.values.flat_map { |d| d[:by_sport].keys }.uniq

      {
        labels: seasons,
        datasets: sports.map do |sport|
          {
            label: format_sport_name(sport),
            data: seasons.map { |s| winter_by_season.dig(s, :by_sport, sport, :total_activities) || 0 },
            backgroundColor: SPORT_COLORS[sport] || DEFAULT_COLOR
          }
        end
      }
    end

    def winter_chart_script(chart_data)
      return '' unless chart_data

      <<~JS
        const winterChartData = #{chart_data.to_json};
        const winterCtx = document.getElementById('winterSeasonChart').getContext('2d');
        new Chart(winterCtx, {
          type: 'bar',
          data: winterChartData,
          options: {
            responsive: true,
            plugins: {
              legend: { position: 'top' }
            },
            scales: {
              x: { stacked: true, grid: { display: false } },
              y: { stacked: true, beginAtZero: true, grid: { color: '#e5e5e5' } }
            },
            onClick: function(evt, elements) {
              if (elements.length > 0) {
                const datasetIndex = elements[0].datasetIndex;
                const index = elements[0].index;
                const sport = winterChartData.datasets[datasetIndex].label.replace(/ /g, '');
                const season = winterChartData.labels[index];
                const ids = activityIds.winterBySeason[season] && activityIds.winterBySeason[season].by_sport[sport] || [];
                showActivityModal(winterChartData.datasets[datasetIndex].label + ' - ' + season, getActivitiesFromIds(ids));
              }
            },
            onHover: function(evt, elements) {
              evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default';
            }
          }
        });
      JS
    end

    def collect_all_activities(stats)
      all = {}

      # Collect from by_sport
      stats[:by_sport].each_value do |s|
        (s[:activities] || []).each { |a| all[a[:id]] = a }
      end

      # Collect from by_year
      stats[:by_year].each_value do |s|
        (s[:activities] || []).each { |a| all[a[:id]] = a }
      end

      # Collect from resorts_by_season
      stats[:resorts_by_season].each_value do |resorts|
        resorts.each_value do |data|
          (data[:activities] || []).each do |a|
            all[a['id']] = {
              id: a['id'],
              name: a['name'] || 'Activity',
              date: a['start_date_local']&.split('T')&.first || '',
              elevation: ((a['total_elevation_gain'] || 0) * 3.28084).round(0),
              hours: ((a['moving_time'] || 0) / 3600.0).round(2)
            }
          end
        end
      end

      # Collect from peaks_by_season
      (stats[:peaks_by_season] || {}).each_value do |peaks|
        peaks.each_value do |data|
          (data[:activities] || []).each do |a|
            all[a['id']] = {
              id: a['id'],
              name: a['name'] || 'Activity',
              date: a['start_date_local']&.split('T')&.first || '',
              elevation: ((a['total_elevation_gain'] || 0) * 3.28084).round(0),
              hours: ((a['moving_time'] || 0) / 3600.0).round(2)
            }
          end
        end
      end

      all
    end

    def format_sport_name(sport)
      sport.gsub(/([a-z])([A-Z])/, '\1 \2')
    end

    def format_number(num)
      return '0' unless num

      num.is_a?(Float) ? num.round(1).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse : num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def format_date(date_str)
      return '' unless date_str

      Time.parse(date_str).strftime('%b %d, %Y')
    end
  end
end
