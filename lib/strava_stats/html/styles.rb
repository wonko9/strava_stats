# frozen_string_literal: true

module StravaStats
  module HTML
    # CSS styles for the stats page.
    # Extracted from HTMLGenerator for maintainability.
    module Styles
      def self.css
        <<~CSS
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

          * { margin: 0; padding: 0; box-sizing: border-box; }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.5;
            padding: 1.5rem;
            font-size: 14px;
          }

          .container { max-width: 1400px; margin: 0 auto; }

          header {
            text-align: center;
            margin-bottom: 1.5rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid var(--border);
          }

          h1 { font-size: 1.75rem; margin-bottom: 0.25rem; color: var(--accent); }
          .subtitle { color: var(--text-secondary); font-size: 0.9rem; }

          h2 {
            font-size: 1.25rem;
            margin-bottom: 1rem;
            color: var(--text-primary);
            font-weight: 700;
            padding-bottom: 0.5rem;
            border-bottom: 3px solid var(--accent);
            display: inline-block;
          }

          h3 { font-size: 1rem; margin-bottom: 0.75rem; color: var(--text-primary); font-weight: 600; }
          .section { margin-bottom: 2rem; }

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

          .stat-value { font-size: 1.5rem; font-weight: 700; color: var(--text-primary); }
          .stat-label { color: var(--text-secondary); font-size: 0.75rem; margin-top: 0.25rem; text-transform: uppercase; letter-spacing: 0.5px; }

          .chart-container {
            background: var(--bg-card);
            border-radius: 8px;
            padding: 1rem;
            margin-bottom: 1rem;
            border: 1px solid var(--border);
            box-shadow: var(--shadow);
          }

          .chart-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 0.75rem; }

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

          th, td { padding: 0.75rem 1rem; text-align: left; border-bottom: 1px solid var(--border); }

          th {
            background: var(--bg-primary);
            font-weight: 600;
            color: var(--text-secondary);
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
          }

          table.sortable th { cursor: pointer; user-select: none; position: relative; padding-right: 1.5rem; }
          table.sortable th:hover { color: var(--accent); }
          table.sortable th::after { content: '⇅'; position: absolute; right: 0.5rem; opacity: 0.3; font-size: 0.65rem; }
          table.sortable th.sort-asc::after { content: '↑'; opacity: 1; color: var(--accent); }
          table.sortable th.sort-desc::after { content: '↓'; opacity: 1; color: var(--accent); }

          tr:last-child td { border-bottom: none; }
          tr:hover { background: #f7f7fa; }
          .number { text-align: right; font-variant-numeric: tabular-nums; }

          .sport-badge {
            display: inline-block;
            padding: 0.15rem 0.5rem;
            border-radius: 9999px;
            font-size: 0.75rem;
            font-weight: 500;
            color: white;
          }

          .resort-section { margin-top: 0.75rem; }
          .resort-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 0.5rem; }

          .resort-card {
            background: var(--bg-card);
            border-radius: 6px;
            padding: 0.5rem 0.75rem;
            border: 1px solid var(--border);
          }

          .resort-name { font-weight: 600; margin-bottom: 0.25rem; color: var(--accent); font-size: 0.85rem; }
          .resort-stats { font-size: 0.75rem; color: var(--text-secondary); }

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

          .tab:hover { color: var(--text-primary); }
          .tab.active { color: var(--accent); border-bottom-color: var(--accent); }
          .tab-content { display: none; }
          .tab-content.active { display: block; }
          .hidden { display: none; }
          .winter-table { margin-top: 0.5rem; }

          .comparison-container { margin-top: 0.5rem; }
          .comparison-grid { display: grid; grid-template-columns: 1fr auto 1fr; gap: 0.75rem; align-items: stretch; }

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

          .comparison-card.current h4 { color: var(--accent); }

          .comparison-stat {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border);
            font-size: 0.8rem;
            height: 28px;
          }

          .comparison-stat:last-child { border-bottom: none; }
          .comparison-stat-label { color: var(--text-secondary); }
          .comparison-stat-value { font-weight: 600; font-variant-numeric: tabular-nums; }

          .comparison-vs { display: flex; flex-direction: column; align-items: center; padding: 0.75rem 0.25rem; }
          .comparison-vs-header { color: var(--text-secondary); font-size: 0.75rem; font-weight: bold; height: 24px; line-height: 24px; }
          .change-indicators { display: flex; flex-direction: column; width: 100%; }

          .change-indicator {
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 0.65rem;
            white-space: nowrap;
            height: 28px;
            border-bottom: 1px solid var(--border);
          }

          .change-indicator:last-child { border-bottom: none; }
          .change-positive { color: #22c55e; }
          .change-negative { color: #ef4444; }
          .change-neutral { color: var(--text-secondary); }

          .sport-selector { margin-bottom: 0.5rem; }

          .sport-selector select, select {
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

          select:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px rgba(252, 76, 2, 0.1); }
          select:hover { border-color: #b8b8c0; }

          .year-selectors { display: flex; align-items: center; gap: 0.5rem; }
          .year-selectors span { color: var(--text-secondary); }

          .comparison-chart-section {
            margin-top: 1rem;
            background: var(--bg-card);
            border-radius: 8px;
            padding: 1rem;
            border: 1px solid var(--border);
            box-shadow: var(--shadow);
          }

          .chart-controls { margin-bottom: 0.5rem; display: flex; align-items: center; gap: 0.35rem; font-size: 0.8rem; }
          .chart-controls label { color: var(--text-secondary); }

          .metric-selector {
            background: var(--bg-secondary);
            color: var(--text-primary);
            border: 1px solid var(--border);
            border-radius: 4px;
            padding: 0.2rem 0.5rem;
            font-size: 0.8rem;
            cursor: pointer;
          }

          .metric-selector:focus { outline: none; border-color: var(--accent); }

          .comparison-selectors { display: flex; gap: 1rem; margin-bottom: 0.75rem; flex-wrap: wrap; align-items: center; font-size: 0.8rem; }
          .comparison-selectors label { color: var(--text-secondary); margin-right: 0.25rem; }

          .generated-at {
            text-align: center;
            color: var(--text-secondary);
            font-size: 0.75rem;
            margin-top: 1.5rem;
            padding-top: 1rem;
            border-top: 1px solid var(--border);
          }

          .chart-tabs { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem; flex-wrap: wrap; gap: 0.5rem; }
          .chart-metric-selector { display: flex; align-items: center; gap: 0.35rem; font-size: 0.8rem; }
          .chart-metric-selector label { color: var(--text-secondary); }

          .chart-metric-selector select {
            background: var(--bg-card);
            color: var(--text-primary);
            border: 1px solid var(--border);
            border-radius: 4px;
            padding: 0.25rem 0.5rem;
            font-size: 0.8rem;
            cursor: pointer;
          }

          /* Modal Styles */
          .modal-overlay {
            display: none;
            position: fixed;
            top: 0; left: 0;
            width: 100%; height: 100%;
            background: rgba(0, 0, 0, 0.5);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            padding: 1rem;
          }

          .modal-overlay.active { display: flex; }

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

          .modal-title { font-size: 1.25rem; font-weight: 700; color: var(--text-primary); }

          .modal-close {
            background: none;
            border: none;
            color: var(--text-secondary);
            font-size: 1.75rem;
            cursor: pointer;
            padding: 0;
            line-height: 1;
          }

          .modal-close:hover { color: var(--accent); }
          .modal-body { padding: 1rem 1.5rem; overflow-y: auto; flex: 1; background: var(--bg-primary); }
          .activity-list { display: flex; flex-direction: column; gap: 0.75rem; }

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

          .activity-item:hover { border-color: var(--accent); box-shadow: 0 2px 8px rgba(252, 76, 2, 0.15); transform: translateY(-1px); }
          .activity-info { display: flex; flex-direction: column; gap: 0.25rem; }
          .activity-name { font-weight: 600; color: var(--text-primary); }
          .activity-date { font-size: 0.8rem; color: var(--text-secondary); }
          .activity-stats { text-align: right; font-size: 0.875rem; color: var(--text-secondary); }
          .activity-stats span { display: block; }
          .strava-link { color: var(--accent); font-size: 0.75rem; margin-top: 0.25rem; font-weight: 500; }

          /* Clickable rows */
          tr.clickable { cursor: pointer; transition: all 0.2s; }
          tr.clickable:hover { background: rgba(252, 76, 2, 0.08) !important; }

          /* Expandable sport chart */
          tr.sport-chart-row { display: none; }
          tr.sport-chart-row.active { display: table-row; }
          tr.sport-chart-row td { padding: 1rem; background: var(--bg-primary); }

          .sport-chart-container { background: var(--bg-card); border-radius: 8px; padding: 1rem; border: 1px solid var(--border); }
          .sport-chart-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem; }
          .sport-chart-title { font-weight: 600; color: var(--text-primary); }

          tr.sport-row-expanded { background: rgba(252, 76, 2, 0.05); }
          .expand-indicator { color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem; }
          tr.sport-row-expanded .expand-indicator::after { content: '▼'; }
          tr:not(.sport-row-expanded) .expand-indicator::after { content: '▶'; }

          .comparison-card.clickable { cursor: pointer; transition: all 0.2s; }
          .comparison-card.clickable:hover { border-color: var(--accent); box-shadow: 0 2px 8px rgba(252, 76, 2, 0.15); }

          @media (max-width: 768px) {
            body { padding: 0.5rem; }
            h1 { font-size: 1.4rem; }
            .chart-row { grid-template-columns: 1fr; }
            .summary-grid { grid-template-columns: repeat(3, 1fr); }
            .comparison-grid { grid-template-columns: 1fr; }
            .comparison-vs { flex-direction: row; padding: 0.25rem; }
          }
        CSS
      end
    end
  end
end
