# frozen_string_literal: true

require 'faraday'
require 'json'
require 'webrick'
require 'uri'

module StravaStats
  class RateLimitError < StandardError
    attr_reader :wait_seconds

    def initialize(message, wait_seconds: 900)
      super(message)
      @wait_seconds = wait_seconds
    end
  end

  class DailyLimitError < StandardError; end

  class StravaAPI
    AUTHORIZE_URL = 'https://www.strava.com/oauth/authorize'
    TOKEN_URL = 'https://www.strava.com/oauth/token'
    API_BASE_URL = 'https://www.strava.com/api/v3'

    SCOPES = 'read,activity:read_all'

    def initialize(client_id:, client_secret:, database:, callback_port: 8888)
      @client_id = client_id
      @client_secret = client_secret
      @database = database
      @callback_port = callback_port
      @access_token = nil

      load_tokens
    end

    def authenticated?
      !@access_token.nil?
    end

    def authorize!
      puts "\n=== Strava Authorization Required ==="
      puts "A browser window will open for you to authorize this application."
      puts "If it doesn't open automatically, visit this URL:\n\n"

      auth_url = build_authorize_url
      puts auth_url
      puts "\n"

      # Try to open browser
      system("open '#{auth_url}'") || system("xdg-open '#{auth_url}'")

      # Start local server to receive callback
      code = wait_for_oauth_callback
      raise 'Authorization failed - no code received' unless code

      # Exchange code for tokens
      exchange_code_for_tokens(code)
      puts "\n✓ Successfully authorized with Strava!"
    end

    def get_athlete
      response = api_request(:get, '/athlete')
      JSON.parse(response.body)
    end

    def get_athlete_stats(athlete_id)
      response = api_request(:get, "/athletes/#{athlete_id}/stats")
      JSON.parse(response.body)
    end

    def get_total_activity_count
      # Get athlete ID from stored tokens
      tokens = @database.get_tokens
      return nil unless tokens && tokens[:athlete]

      athlete_id = tokens[:athlete]['id']
      return nil unless athlete_id

      stats = get_athlete_stats(athlete_id)

      # Sum up all activity counts
      total = 0
      %w[all_ride_totals all_run_totals all_swim_totals].each do |key|
        total += stats.dig(key, 'count') || 0
      end

      # The stats endpoint doesn't include all activity types, so this is approximate
      # We'll return the stats hash so caller can show breakdown if desired
      { total_estimate: total, stats: stats }
    end

    def get_activities(page: 1, per_page: 100, after: nil, before: nil)
      params = { page: page, per_page: per_page }
      params[:after] = after if after
      params[:before] = before if before

      response = api_request(:get, '/athlete/activities', params)
      JSON.parse(response.body)
    end

    def get_activity(activity_id)
      response = api_request(:get, "/activities/#{activity_id}")
      JSON.parse(response.body)
    end

    def get_all_activities(after: nil, &block)
      all_activities = []
      page = 1
      per_page = 100

      loop do
        puts "  Fetching page #{page}..." if page > 1 || after
        activities = get_activities(page: page, per_page: per_page, after: after)

        break if activities.empty?

        activities.each do |activity|
          all_activities << activity
          yield activity if block_given?
        end

        break if activities.length < per_page

        page += 1

        # Rate limiting - Strava allows 100 requests per 15 minutes
        sleep(0.5)
      end

      all_activities
    end

    private

    def load_tokens
      tokens = @database.get_tokens
      return unless tokens

      if tokens[:expires_at] && tokens[:expires_at] < Time.now.to_i
        # Token expired, refresh it
        refresh_access_token(tokens[:refresh_token])
      else
        @access_token = tokens[:access_token]
        @refresh_token = tokens[:refresh_token]
        @expires_at = tokens[:expires_at]
      end
    end

    def build_authorize_url
      params = {
        client_id: @client_id,
        redirect_uri: "http://localhost:#{@callback_port}/callback",
        response_type: 'code',
        scope: SCOPES
      }

      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    def wait_for_oauth_callback
      code = nil
      server = WEBrick::HTTPServer.new(
        Port: @callback_port,
        Logger: WEBrick::Log.new('/dev/null'),
        AccessLog: []
      )

      server.mount_proc '/callback' do |req, res|
        code = req.query['code']
        error = req.query['error']

        if error
          res.body = <<~HTML
            <html><body>
            <h1>Authorization Failed</h1>
            <p>Error: #{error}</p>
            <p>You can close this window.</p>
            </body></html>
          HTML
        elsif code
          res.body = <<~HTML
            <html><body>
            <h1>Authorization Successful!</h1>
            <p>You can close this window and return to the terminal.</p>
            </body></html>
          HTML
        end

        Thread.new { sleep 1; server.shutdown }
      end

      puts "Waiting for authorization callback on port #{@callback_port}..."
      server.start

      code
    end

    def exchange_code_for_tokens(code)
      conn = Faraday.new(url: TOKEN_URL)
      response = conn.post do |req|
        req.body = {
          client_id: @client_id,
          client_secret: @client_secret,
          code: code,
          grant_type: 'authorization_code'
        }
      end

      raise "Token exchange failed: #{response.body}" unless response.success?

      data = JSON.parse(response.body)
      save_tokens(data)
    end

    def refresh_access_token(refresh_token)
      conn = Faraday.new(url: TOKEN_URL)
      response = conn.post do |req|
        req.body = {
          client_id: @client_id,
          client_secret: @client_secret,
          refresh_token: refresh_token,
          grant_type: 'refresh_token'
        }
      end

      raise "Token refresh failed: #{response.body}" unless response.success?

      data = JSON.parse(response.body)
      save_tokens(data)
    end

    def save_tokens(data)
      @access_token = data['access_token']
      @refresh_token = data['refresh_token']
      @expires_at = data['expires_at']

      @database.save_tokens(
        access_token: @access_token,
        refresh_token: @refresh_token,
        expires_at: @expires_at,
        athlete: data['athlete']
      )
    end

    def api_request(method, path, params = {})
      ensure_valid_token!

      url = "#{API_BASE_URL}#{path}"

      conn = Faraday.new do |f|
        f.request :url_encoded
      end

      response = conn.send(method, url) do |req|
        req.headers['Authorization'] = "Bearer #{@access_token}"
        req.params = params if method == :get && params.any?
        req.body = params if method != :get && params.any?
      end

      if response.status == 401
        # Token might have expired, try refreshing
        refresh_access_token(@refresh_token)
        return api_request(method, path, params)
      end

      if response.status == 429
        # Rate limit exceeded - check headers for reset time
        # Strava returns X-RateLimit-Limit and X-RateLimit-Usage headers
        # Format: "15-minute-limit,daily-limit" and "15-min-usage,daily-usage"
        usage = response.headers['X-RateLimit-Usage']&.split(',')&.map(&:to_i) || [0, 0]
        limits = response.headers['X-RateLimit-Limit']&.split(',')&.map(&:to_i) || [100, 1000]

        if usage[1] >= limits[1]
          raise DailyLimitError, "Daily API limit reached (#{usage[1]}/#{limits[1]}). Try again tomorrow."
        else
          # 15-minute limit - wait and retry
          raise RateLimitError.new(
            "15-minute rate limit exceeded (#{usage[0]}/#{limits[0]})",
            wait_seconds: 900
          )
        end
      end

      raise "API request failed (#{response.status}): #{response.body}" unless response.success?

      response
    end

    def ensure_valid_token!
      raise 'Not authenticated. Run authorize! first.' unless @access_token

      return unless @expires_at && @expires_at < Time.now.to_i + 60

      refresh_access_token(@refresh_token)
    end
  end
end
