# frozen_string_literal: true

module StravaStats
  module HTML
    # JavaScript for the stats page.
    # Extracted from HTMLGenerator for maintainability.
    module Scripts
      def self.sport_colors
        Formatters::SPORT_COLORS
      end

      def self.default_color
        Formatters::DEFAULT_COLOR
      end

      # Generate the main JavaScript code with embedded data
      def self.generate(stats:, by_year_chart:, by_sport_chart:, winter_season_chart:, all_activities:)
        activity_ids = build_activity_ids(stats)
        sport_yearly_stats = build_sport_yearly_stats(stats)

        <<~JS
          // All activities stored once by ID
          var allActivities = #{all_activities.to_json};

          // Activity IDs grouped for lookups
          var activityIds = #{activity_ids.to_json};

          // Yearly stats by sport for expandable charts
          var sportYearlyStats = #{sport_yearly_stats.to_json};

          #{core_functions}
          #{chart_initialization(by_year_chart, by_sport_chart)}
          #{winter_chart_initialization(winter_season_chart)}
          #{tab_switching}
          #{year_comparison_functions}
          #{season_comparison_functions}
          #{shared_comparison_functions}
          #{modal_functions}
          #{table_sorting}
        JS
      end

      def self.build_activity_ids(stats)
        {
          bySport: stats[:by_sport].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } },
          byYear: stats[:by_year].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } },
          bySportAndYear: stats[:by_sport_and_year].transform_values { |years|
            years.transform_values { |s| (s[:activities] || []).map { |a| a[:id] } }
          },
          winterBySeason: stats[:winter_by_season].transform_values { |d|
            {
              totals: (d[:totals][:activities] || []).map { |a| a[:id] },
              by_sport: d[:by_sport].transform_values { |s| (s[:activities] || []).map { |a| a[:id] } }
            }
          }
        }
      end

      def self.build_sport_yearly_stats(stats)
        stats[:by_sport_and_year].transform_values { |years|
          years.transform_values { |s| s.reject { |k, _| k == :activities } }
        }
      end

      def self.core_functions
        <<~JS
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
              chartRow.classList.remove('active');
              row.classList.remove('sport-row-expanded');
            } else {
              chartRow.classList.add('active');
              row.classList.add('sport-row-expanded');
              if (!sportCharts[sport]) renderSportChart(sport);
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
              data: { labels: years, datasets: [{ label: getMetricLabel(metric), data: values, backgroundColor: color }] },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { display: false },
                  tooltip: {
                    callbacks: {
                      title: tooltipItems => tooltipItems[0].label,
                      beforeLabel: () => null,
                      label: tooltipItem => {
                        const currentMetric = document.getElementById('sport-chart-metric-' + sport).value;
                        const labels = { 'total_activities': 'Total Activities', 'total_days': 'Total Days', 'total_time_hours': 'Total Hours', 'total_distance_miles': 'Total Miles', 'total_elevation_feet': 'Total Vertical (ft)', 'total_calories': 'Total Calories' };
                        return (labels[currentMetric] || currentMetric) + ': ' + tooltipItem.raw.toLocaleString();
                      },
                      afterLabel: () => null
                    }
                  }
                },
                scales: {
                  y: { beginAtZero: true, grid: { color: '#e5e5e5' }, ticks: { precision: 0 } },
                  x: { grid: { display: false } }
                },
                onClick: (evt, elements) => {
                  if (elements.length > 0) {
                    const year = years[elements[0].index];
                    const ids = activityIds.bySportAndYear[sport] && activityIds.bySportAndYear[sport][year] || [];
                    showActivityModal(formatSportName(sport) + ' - ' + year, getActivitiesFromIds(ids));
                  }
                },
                onHover: (evt, elements) => { evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default'; }
              }
            });
          }

          function updateSportChart(sport) {
            if (sportCharts[sport]) { sportCharts[sport].destroy(); sportCharts[sport] = null; }
            renderSportChart(sport);
          }

          function getSportColor(sport) {
            const colors = #{sport_colors.to_json};
            return colors[sport] || '#{default_color}';
          }

          function formatSportName(sport) { return sport.replace(/([a-z])([A-Z])/g, '$1 $2'); }

          function getMetricLabel(metric) {
            const labels = { 'total_activities': 'Total Activities', 'total_days': 'Total Days', 'total_time_hours': 'Total Hours', 'total_distance_miles': 'Total Miles', 'total_elevation_feet': 'Total Vertical (ft)', 'total_calories': 'Total Calories' };
            return labels[metric] || metric;
          }

          Chart.defaults.color = '#6d6d78';
          Chart.defaults.borderColor = '#e5e5e5';
          Chart.defaults.plugins.tooltip.displayColors = false;
        JS
      end

      def self.chart_initialization(by_year_chart, by_sport_chart)
        <<~JS
          // By Year Chart
          new Chart(document.getElementById('byYearChart').getContext('2d'), {
            type: 'bar',
            data: #{by_year_chart.to_json},
            options: {
              responsive: true,
              plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => 'Activities: ' + ctx.raw.toLocaleString() } } },
              scales: { y: { beginAtZero: true, grid: { color: '#e5e5e5' } }, x: { grid: { display: false } } }
            }
          });

          // By Sport Chart
          new Chart(document.getElementById('bySportChart').getContext('2d'), {
            type: 'doughnut',
            data: #{by_sport_chart.to_json},
            options: {
              responsive: true,
              plugins: {
                legend: { position: 'right', labels: { padding: 15 } },
                tooltip: { callbacks: { label: ctx => ctx.label + ': ' + ctx.raw.toLocaleString() + ' activities' } }
              }
            }
          });
        JS
      end

      def self.winter_chart_initialization(chart_data)
        return '' if chart_data[:labels].empty?

        <<~JS
          const winterChartData = #{chart_data.to_json};
          new Chart(document.getElementById('winterSeasonChart').getContext('2d'), {
            type: 'bar',
            data: winterChartData,
            options: {
              responsive: true,
              plugins: { legend: { position: 'top' }, tooltip: { callbacks: { label: ctx => ctx.dataset.label + ': ' + ctx.raw.toLocaleString() + ' activities' } } },
              scales: { x: { stacked: true, grid: { display: false } }, y: { stacked: true, beginAtZero: true, grid: { color: '#e5e5e5' } } },
              onClick: (evt, elements) => {
                if (elements.length > 0) {
                  const season = winterChartData.labels[elements[0].index];
                  const sport = winterChartData.datasets[elements[0].datasetIndex].label.replace(/ /g, '');
                  const ids = activityIds.winterBySeason[season] && activityIds.winterBySeason[season].by_sport[sport] || [];
                  showActivityModal(winterChartData.datasets[elements[0].datasetIndex].label + ' - ' + season, getActivitiesFromIds(ids));
                }
              },
              onHover: (evt, elements) => { evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default'; }
            }
          });
        JS
      end

      def self.tab_switching
        <<~JS
          function showSportTab(sport) {
            document.querySelectorAll('.sport-tab-content').forEach(el => el.classList.remove('active'));
            document.getElementById('sport-' + sport).classList.add('active');
          }

          function showWinterTab(sport) {
            document.querySelectorAll('.winter-table').forEach(el => el.classList.add('hidden'));
            document.querySelectorAll('#winterTabs .tab').forEach(el => el.classList.remove('active'));
            document.getElementById('winter-' + sport).classList.remove('hidden');
            event.target.classList.add('active');
          }
        JS
      end

      def self.year_comparison_functions
        <<~JS
          let yearComparisonData = null;
          let yearComparisonChart = null;

          function initYearComparison() {
            const dataEl = document.getElementById('year-comparison-data');
            if (!dataEl) return;
            yearComparisonData = JSON.parse(dataEl.textContent || '{}');
            if (Object.keys(yearComparisonData).length === 0) return;
            populateYearSelectors(document.getElementById('yearComparisonSport').value);
            updateYearComparisonDisplay();
          }

          function populateYearSelectors(sport) {
            const data = yearComparisonData[sport];
            if (!data) return;
            const years = data.available_years;
            document.getElementById('yearComparisonYear1').innerHTML = years.map(y => `<option value="${y}">${y}</option>`).join('');
            document.getElementById('yearComparisonYear2').innerHTML = years.map(y => `<option value="${y}">${y}</option>`).join('');
            if (years.length >= 2) {
              document.getElementById('yearComparisonYear1').value = years[0];
              document.getElementById('yearComparisonYear2').value = years[1];
            }
          }

          function onYearSportChange() {
            populateYearSelectors(document.getElementById('yearComparisonSport').value);
            updateYearComparisonDisplay();
          }

          function updateYearComparisonDisplay() {
            const sport = document.getElementById('yearComparisonSport').value;
            const year1 = document.getElementById('yearComparisonYear1').value;
            const year2 = document.getElementById('yearComparisonYear2').value;
            const data = yearComparisonData[sport];
            if (!data) return;
            const data1 = data.yearly_data[year1], data2 = data.yearly_data[year2];
            if (!data1 || !data2) return;
            document.getElementById('year-comparison-label1').textContent = year1;
            document.getElementById('year-comparison-label2').textContent = year2;
            document.getElementById('year-comparison-stats1').innerHTML = formatComparisonStats(data1.stats);
            document.getElementById('year-comparison-stats2').innerHTML = formatComparisonStats(data2.stats);
            document.getElementById('year-comparison-changes').innerHTML = formatChangeIndicators(calculateChanges(data1.stats, data2.stats));
            updateYearComparisonChart();
          }

          function updateYearComparison() { updateYearComparisonDisplay(); }

          function updateYearComparisonChart() {
            const sport = document.getElementById('yearComparisonSport').value;
            const year1 = document.getElementById('yearComparisonYear1').value;
            const year2 = document.getElementById('yearComparisonYear2').value;
            const metric = document.getElementById('year-comparison-metric').value;
            const data = yearComparisonData[sport];
            if (!data) return;
            const data1 = data.yearly_data[year1], data2 = data.yearly_data[year2];
            if (!data1 || !data2) return;
            const canvas = document.getElementById('year-comparison-chart');
            if (!canvas) return;
            if (yearComparisonChart) yearComparisonChart.destroy();
            const points1 = (data1.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
            const points2 = (data2.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
            const chartOptions = getComparisonChartOptions(metric, 'Day of Year', points1, points2, year1, year2);
            chartOptions.onClick = (evt, elements) => {
              if (elements.length > 0) {
                const clickedYear = elements[0].datasetIndex === 0 ? year1 : year2;
                showYearComparisonActivities(elements[0].datasetIndex === 0 ? 1 : 2);
              }
            };
            chartOptions.onHover = (evt, elements) => { evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default'; };
            yearComparisonChart = new Chart(canvas.getContext('2d'), {
              type: 'line',
              data: {
                datasets: [
                  { label: year1, data: points1, borderColor: '#FC4C02', backgroundColor: 'rgba(252, 76, 2, 0.1)', fill: true, tension: 0.3, pointRadius: 2, pointHoverRadius: 5 },
                  { label: year2, data: points2, borderColor: '#6b7280', backgroundColor: 'rgba(107, 114, 128, 0.1)', fill: true, tension: 0.3, pointRadius: 2, pointHoverRadius: 5, borderDash: [5, 5] }
                ]
              },
              options: chartOptions
            });
          }

          function showYearComparisonActivities(cardNum) {
            const sport = document.getElementById('yearComparisonSport').value;
            const year = cardNum === 1 ? document.getElementById('yearComparisonYear1').value : document.getElementById('yearComparisonYear2').value;
            const ids = activityIds.bySportAndYear[sport] && activityIds.bySportAndYear[sport][year] || [];
            showActivityModal(document.getElementById('yearComparisonSport').options[document.getElementById('yearComparisonSport').selectedIndex].text + ' - ' + year, getActivitiesFromIds(ids));
          }
        JS
      end

      def self.season_comparison_functions
        <<~JS
          let seasonComparisonData = null;
          let seasonComparisonChart = null;

          function initSeasonComparison() {
            const dataEl = document.getElementById('season-comparison-data');
            if (!dataEl) return;
            seasonComparisonData = JSON.parse(dataEl.textContent || '{}');
            if (Object.keys(seasonComparisonData).length === 0) return;
            populateSeasonSelectors(document.getElementById('seasonComparisonSport').value);
            updateSeasonComparisonDisplay();
          }

          function populateSeasonSelectors(sport) {
            const data = seasonComparisonData[sport];
            if (!data) return;
            const seasons = data.available_seasons;
            document.getElementById('seasonComparisonSeason1').innerHTML = seasons.map(s => `<option value="${s}">${s}</option>`).join('');
            document.getElementById('seasonComparisonSeason2').innerHTML = seasons.map(s => `<option value="${s}">${s}</option>`).join('');
            if (seasons.length >= 2) {
              document.getElementById('seasonComparisonSeason1').value = seasons[0];
              document.getElementById('seasonComparisonSeason2').value = seasons[1];
            }
          }

          function onSeasonSportChange() {
            populateSeasonSelectors(document.getElementById('seasonComparisonSport').value);
            updateSeasonComparisonDisplay();
          }

          function updateSeasonComparisonDisplay() {
            const sport = document.getElementById('seasonComparisonSport').value;
            const season1 = document.getElementById('seasonComparisonSeason1').value;
            const season2 = document.getElementById('seasonComparisonSeason2').value;
            const data = seasonComparisonData[sport];
            if (!data) return;
            const data1 = data.season_data[season1], data2 = data.season_data[season2];
            if (!data1 || !data2) return;
            document.getElementById('season-comparison-label1').textContent = season1 + ' Season';
            document.getElementById('season-comparison-label2').textContent = season2 + ' Season';
            document.getElementById('season-comparison-stats1').innerHTML = formatComparisonStats(data1.stats);
            document.getElementById('season-comparison-stats2').innerHTML = formatComparisonStats(data2.stats);
            document.getElementById('season-comparison-changes').innerHTML = formatChangeIndicators(calculateChanges(data1.stats, data2.stats));
            updateSeasonComparisonChart();
          }

          function updateSeasonComparison() { updateSeasonComparisonDisplay(); }

          function updateSeasonComparisonChart() {
            const sport = document.getElementById('seasonComparisonSport').value;
            const season1 = document.getElementById('seasonComparisonSeason1').value;
            const season2 = document.getElementById('seasonComparisonSeason2').value;
            const metric = document.getElementById('season-comparison-metric').value;
            const data = seasonComparisonData[sport];
            if (!data) return;
            const data1 = data.season_data[season1], data2 = data.season_data[season2];
            if (!data1 || !data2) return;
            const canvas = document.getElementById('season-comparison-chart');
            if (!canvas) return;
            if (seasonComparisonChart) seasonComparisonChart.destroy();
            const points1 = (data1.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
            const points2 = (data2.cumulative_clipped || []).map(d => ({ x: d.day, y: d[metric], date: d.date }));
            const chartOptions = getComparisonChartOptions(metric, 'Day of Season (from Sep 1)', points1, points2, season1, season2);
            chartOptions.onClick = (evt, elements) => {
              if (elements.length > 0) {
                showSeasonComparisonActivities(elements[0].datasetIndex === 0 ? 1 : 2);
              }
            };
            chartOptions.onHover = (evt, elements) => { evt.native.target.style.cursor = elements.length > 0 ? 'pointer' : 'default'; };
            seasonComparisonChart = new Chart(canvas.getContext('2d'), {
              type: 'line',
              data: {
                datasets: [
                  { label: season1, data: points1, borderColor: '#FC4C02', backgroundColor: 'rgba(252, 76, 2, 0.1)', fill: true, tension: 0.3, pointRadius: 2, pointHoverRadius: 5 },
                  { label: season2, data: points2, borderColor: '#6b7280', backgroundColor: 'rgba(107, 114, 128, 0.1)', fill: true, tension: 0.3, pointRadius: 2, pointHoverRadius: 5, borderDash: [5, 5] }
                ]
              },
              options: chartOptions
            });
          }

          function showSeasonComparisonActivities(cardNum) {
            const sport = document.getElementById('seasonComparisonSport').value;
            const season = cardNum === 1 ? document.getElementById('seasonComparisonSeason1').value : document.getElementById('seasonComparisonSeason2').value;
            const ids = activityIds.winterBySeason[season] && activityIds.winterBySeason[season].by_sport[sport] || [];
            showActivityModal(document.getElementById('seasonComparisonSport').options[document.getElementById('seasonComparisonSport').selectedIndex].text + ' - ' + season, getActivitiesFromIds(ids));
          }
        JS
      end

      def self.shared_comparison_functions
        <<~JS
          function getComparisonChartOptions(metric, xAxisLabel, points1, points2, label1, label2) {
            const suffixes = { elevation: ' ft', miles: ' mi', hours: ' hrs', calories: ' cal' };
            const suffix = suffixes[metric] || '';
            function getCumulativeAt(points, day) {
              let result = null;
              for (const p of points) { if (p.x <= day) result = p; else break; }
              return result;
            }
            const yearMonthStarts = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
            const yearMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            const seasonMonthStarts = [1, 31, 62, 92, 123, 153, 184, 214, 245, 275, 306, 336];
            const seasonMonths = ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];
            return {
              responsive: true,
              maintainAspectRatio: false,
              interaction: { mode: 'nearest', axis: 'x', intersect: false },
              plugins: {
                legend: { position: 'top' },
                tooltip: {
                  callbacks: {
                    title: ctx => { const day = ctx[0].raw.x; const p1 = getCumulativeAt(points1, day); const p2 = getCumulativeAt(points2, day); return (p1 && p1.date) || (p2 && p2.date) || 'Day ' + day; },
                    label: () => null,
                    afterBody: ctx => { const day = ctx[0].raw.x; const p1 = getCumulativeAt(points1, day); const p2 = getCumulativeAt(points2, day); return [label1 + ': ' + (p1 ? p1.y.toLocaleString() : '0') + suffix, label2 + ': ' + (p2 ? p2.y.toLocaleString() : '0') + suffix]; }
                  },
                  filter: item => item.text !== null
                }
              },
              scales: {
                x: {
                  type: 'linear', min: 1, max: xAxisLabel.includes('Season') ? 365 : 366,
                  title: { display: false }, grid: { color: '#e5e5e5' },
                  ticks: {
                    autoSkip: false, maxRotation: 0,
                    callback: function(value) {
                      if (xAxisLabel.includes('Season')) { const idx = seasonMonthStarts.indexOf(value); return idx >= 0 ? seasonMonths[idx] : ''; }
                      else { const idx = yearMonthStarts.indexOf(value); return idx >= 0 ? yearMonths[idx] : ''; }
                    }
                  },
                  afterBuildTicks: function(axis) {
                    axis.ticks = (xAxisLabel.includes('Season') ? seasonMonthStarts : yearMonthStarts).map(v => ({value: v}));
                  }
                },
                y: { beginAtZero: true, title: { display: true, text: getCumulativeMetricLabel(metric) }, grid: { color: '#e5e5e5' } }
              }
            };
          }

          function getCumulativeMetricLabel(metric) {
            const labels = { activities: 'Cumulative Activities', hours: 'Cumulative Hours', miles: 'Cumulative Miles', elevation: 'Cumulative Vertical (ft)', calories: 'Cumulative Calories' };
            return labels[metric] || metric;
          }

          function formatComparisonStats(stats) {
            return `<div class="comparison-stat"><span class="comparison-stat-label">Activities</span><span class="comparison-stat-value">${formatNumber(stats.total_activities)}</span></div>
              <div class="comparison-stat"><span class="comparison-stat-label">Days</span><span class="comparison-stat-value">${formatNumber(stats.total_days)}</span></div>
              <div class="comparison-stat"><span class="comparison-stat-label">Hours</span><span class="comparison-stat-value">${formatNumber(stats.total_time_hours)}</span></div>
              <div class="comparison-stat"><span class="comparison-stat-label">Miles</span><span class="comparison-stat-value">${formatNumber(stats.total_distance_miles)}</span></div>
              <div class="comparison-stat"><span class="comparison-stat-label">Vertical (ft)</span><span class="comparison-stat-value">${formatNumber(stats.total_elevation_feet)}</span></div>
              <div class="comparison-stat"><span class="comparison-stat-label">Calories</span><span class="comparison-stat-value">${formatNumber(stats.total_calories)}</span></div>`;
          }

          function calculateChanges(current, previous) {
            const keys = ['total_activities', 'total_days', 'total_time_hours', 'total_distance_miles', 'total_elevation_feet', 'total_calories'];
            const changes = {};
            keys.forEach(key => { const curr = current[key] || 0, prev = previous[key] || 0, diff = curr - prev; changes[key] = { diff, pct: prev === 0 ? (curr === 0 ? 0 : 100) : Math.round((diff / prev) * 100) }; });
            return changes;
          }

          function formatChangeIndicators(changes) {
            const keys = ['total_activities', 'total_days', 'total_time_hours', 'total_distance_miles', 'total_elevation_feet', 'total_calories'];
            return '<div class="change-indicators">' + keys.map(key => {
              const c = changes[key], cls = c.pct > 0 ? 'change-positive' : c.pct < 0 ? 'change-negative' : 'change-neutral';
              const arrow = c.pct > 0 ? '↑' : c.pct < 0 ? '↓' : '−';
              const diffVal = Math.abs(c.diff) >= 1000 ? c.diff.toLocaleString() : (Number.isInteger(c.diff) ? c.diff : c.diff.toFixed(1));
              return `<div class="change-indicator ${cls}">${arrow}${Math.abs(c.pct)}% (${c.diff > 0 ? '+' : ''}${diffVal})</div>`;
            }).join('') + '</div>';
          }

          function formatNumber(num) { return (num === null || num === undefined) ? '0' : num.toLocaleString(); }

          document.addEventListener('DOMContentLoaded', function() { initYearComparison(); initSeasonComparison(); });
        JS
      end

      def self.modal_functions
        <<~JS
          function showActivityModal(title, activities) {
            document.getElementById('modalTitle').textContent = title;
            const list = document.getElementById('activityList');
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

          function closeActivityModal() { document.getElementById('activityModal').classList.remove('active'); }
          function formatActivityDate(dateStr) { return new Date(dateStr).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' }); }
          document.addEventListener('keydown', e => { if (e.key === 'Escape') closeActivityModal(); });
        JS
      end

      def self.table_sorting
        <<~JS
          document.querySelectorAll('table.sortable').forEach(table => {
            const headers = table.querySelectorAll('th');
            const tbody = table.querySelector('tbody');
            headers.forEach((header, columnIndex) => {
              header.addEventListener('click', () => {
                const allRows = Array.from(tbody.querySelectorAll('tr'));
                const dataRows = allRows.filter(r => !r.classList.contains('sport-chart-row'));
                const isAscending = header.classList.contains('sort-asc');
                headers.forEach(h => h.classList.remove('sort-asc', 'sort-desc'));
                dataRows.sort((a, b) => {
                  const aCell = a.cells[columnIndex], bCell = b.cells[columnIndex];
                  if (!aCell || !bCell) return 0;
                  let aVal = aCell.dataset.sort !== undefined ? aCell.dataset.sort : aCell.textContent.trim();
                  let bVal = bCell.dataset.sort !== undefined ? bCell.dataset.sort : bCell.textContent.trim();
                  const aNum = parseFloat(aVal.replace(/,/g, '')), bNum = parseFloat(bVal.replace(/,/g, ''));
                  if (!isNaN(aNum) && !isNaN(bNum)) return isAscending ? aNum - bNum : bNum - aNum;
                  return isAscending ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
                });
                header.classList.add(isAscending ? 'sort-desc' : 'sort-asc');
                dataRows.forEach(row => {
                  tbody.appendChild(row);
                  const chartRowId = row.id ? row.id.replace('sport-row-', 'sport-chart-row-') : null;
                  const chartRow = chartRowId ? document.getElementById(chartRowId) : null;
                  if (chartRow) tbody.appendChild(chartRow);
                });
              });
            });
          });
        JS
      end
    end
  end
end
