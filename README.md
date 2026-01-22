# Strava Stats

A Ruby CLI tool that syncs your Strava activities and generates a beautiful HTML dashboard with stats, charts, and year-over-year comparisons. Includes automatic matching of skiing/snowboarding activities to resorts and backcountry peaks.

## Features

- Sync all activities from Strava with automatic rate limit handling
- Generate an interactive HTML dashboard with:
  - Stats by sport, year, and season
  - Winter sports breakdowns by ski resort
  - Backcountry skiing matched to mountain peaks
  - Year-over-year and season-over-season comparisons with charts
  - Clickable charts that show individual activities with links back to Strava
- GPS-based matching of activities to ski resorts and peaks
- Handles Strava API rate limits gracefully (pauses and resumes automatically)

## Requirements

- Ruby 3.0+
- Bundler
- A Strava API application (free)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/wonko9/strava_stats.git
   cd strava_stats
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Create your config file:
   ```bash
   cp config.yml.example config.yml
   ```

4. Get your Strava API credentials:
   - Go to https://www.strava.com/settings/api
   - Create an application (use `http://localhost:8888/callback` as the redirect URI)
   - Copy your Client ID and Client Secret

5. Edit `config.yml` with your credentials:
   ```yaml
   strava:
     client_id: YOUR_CLIENT_ID
     client_secret: YOUR_CLIENT_SECRET
   ```

## Usage

### First-time setup

Authorize with Strava (opens browser for OAuth):
```bash
bin/strava_stats auth
```

### Sync and generate stats

Sync activities and generate the HTML dashboard:
```bash
bin/strava_stats
```

Or run sync and generate separately:
```bash
bin/strava_stats sync
bin/strava_stats generate
```

### Commands

| Command | Description |
|---------|-------------|
| `bin/strava_stats` | Default: sync activities and generate HTML |
| `bin/strava_stats auth` | Authorize with Strava (required on first run) |
| `bin/strava_stats sync` | Sync activities from Strava |
| `bin/strava_stats sync --full` | Force full sync (ignore last sync time) |
| `bin/strava_stats generate` | Generate HTML stats page |
| `bin/strava_stats fetch_details` | Fetch detailed data (calories, etc.) for activities missing it |
| `bin/strava_stats refresh ID [ID...]` | Re-fetch specific activities from Strava |
| `bin/strava_stats status` | Show sync status |
| `bin/strava_stats resorts` | List all resorts in database |
| `bin/strava_stats resorts --add "Name,Country,Region,Lat,Lng"` | Add a custom resort |
| `bin/strava_stats peaks` | List all peaks in database |
| `bin/strava_stats peaks --add "Name,Country,Region,Lat,Lng,Elev,Radius"` | Add a custom peak |

### Viewing the dashboard

After generating, open the HTML file in your browser:
```bash
open output/index.html
```

## Configuration

The `config.yml` file supports these options:

```yaml
strava:
  client_id: YOUR_CLIENT_ID
  client_secret: YOUR_CLIENT_SECRET

oauth:
  callback_port: 8888  # Port for OAuth callback (default: 8888)

database:
  path: data/strava_stats.db  # SQLite database location

output:
  path: output/index.html  # Generated HTML location
```

## Data Files

- `data/resorts.yml` - Ski resort database with GPS coordinates
- `data/peaks.yml` - Mountain peaks database for backcountry matching

## Rate Limits

Strava API has rate limits (100 requests per 15 minutes, 1000 per day). This tool handles them automatically:
- Pauses and displays a countdown when limits are hit
- Progress is saved, so you can stop and resume later
- Initial sync of many years of activities may take multiple sessions

## License

MIT
