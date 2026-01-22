# frozen_string_literal: true

require_relative 'formatters'

module StravaStats
  module HTML
    # HTML section generators for the stats page.
    # Extracted from HTMLGenerator for maintainability.
    module Sections
      extend Formatters

      class << self
        def summary_section(stats)
          <<~HTML
            <div class="section">
              <h2>All-Time Summary</h2>
              <div class="summary-grid">
                #{stat_card(stats[:total_activities], 'Total Activities')}
                #{stat_card(stats[:total_sports], 'Sports')}
                #{stat_card(stats[:total_distance_miles], 'Total Miles')}
                #{stat_card(stats[:total_elevation_feet], 'Total Vertical (ft)')}
                #{stat_card(stats[:total_time_hours], 'Total Hours')}
                #{stat_card(stats[:total_calories], 'Total Calories')}
              </div>
            </div>
          HTML
        end

        def stat_card(value, label)
          <<~HTML
            <div class="stat-card">
              <div class="stat-value">#{format_number(value)}</div>
              <div class="stat-label">#{label}</div>
            </div>
          HTML
        end

        def charts_section
          <<~HTML
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
          HTML
        end

        def sports_section(by_sport)
          <<~HTML
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
                  #{by_sport.map { |sport, s| sport_row(sport, s) }.join("\n")}
                </tbody>
              </table>
            </div>
          HTML
        end

        def sport_row(sport, stats)
          color = Formatters::SPORT_COLORS[sport] || Formatters::DEFAULT_COLOR
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
                  <div style="height: 200px;"><canvas id="sport-chart-#{sport}"></canvas></div>
                </div>
              </td>
            </tr>
          HTML
        end

        def years_section(by_year, by_sport_and_year)
          sport_options = by_sport_and_year
            .sort_by { |_, years| -years.values.sum { |s| s[:total_activities] } }
            .map { |sport, _| "<option value=\"#{sport}\">#{format_sport_name(sport)}</option>" }
            .join("\n")

          sport_tabs = by_sport_and_year
            .sort_by { |_, years| -years.values.sum { |s| s[:total_activities] } }
            .map { |sport, years| sport_year_tab(sport, years) }
            .join("\n")

          <<~HTML
            <div class="section">
              <h2>Stats by Year</h2>
              <div class="sport-selector" style="margin-bottom: 1rem;">
                <label>Sport:</label>
                <select id="sportYearSelect" onchange="showSportTab(this.value)">
                  <option value="All">All</option>
                  #{sport_options}
                </select>
              </div>
              #{all_years_tab(by_year)}
              #{sport_tabs}
            </div>
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
                <tbody>#{by_year.map { |year, s| year_row(year, s) }.join("\n")}</tbody>
              </table>
            </div>
          HTML
        end

        def sport_year_tab(sport, years)
          <<~HTML
            <div id="sport-#{sport}" class="tab-content sport-tab-content">
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
                <tbody>#{years.map { |year, s| year_row(year, s, sport: sport) }.join("\n")}</tbody>
              </table>
            </div>
          HTML
        end

        def year_row(year, stats, sport: nil)
          onclick = if sport
                      "showActivityModal('#{format_sport_name(sport)} - #{year}', getActivitiesFromIds(activityIds.bySportAndYear['#{sport}'] && activityIds.bySportAndYear['#{sport}']['#{year}'] || []))"
                    else
                      "showActivityModal('#{year}', getActivitiesFromIds(activityIds.byYear['#{year}'] || []))"
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

        def activity_modal
          <<~HTML
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
          HTML
        end
      end
    end
  end
end
