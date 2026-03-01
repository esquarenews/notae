require "json"
require "net/http"
require "uri"

module Kalendarium
  class GoogleOauthService
    AUTHORIZATION_ENDPOINT = URI("https://accounts.google.com/o/oauth2/v2/auth")
    TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")
    CALENDAR_READONLY_SCOPE = "https://www.googleapis.com/auth/calendar.readonly".freeze
    REQUEST_OPEN_TIMEOUT_SECONDS = 10
    REQUEST_TIMEOUT_SECONDS = 30

    class Error < StandardError; end

    def initialize(client_id: nil, client_secret: nil)
      @client_id = client_id.to_s.strip.presence || ENV["GOOGLE_OAUTH_CLIENT_ID"].to_s.strip.presence || ENV["GOOGLE_CLIENT_ID"].to_s.strip.presence
      @client_secret = client_secret.to_s.strip.presence || ENV["GOOGLE_OAUTH_CLIENT_SECRET"].to_s.strip.presence || ENV["GOOGLE_CLIENT_SECRET"].to_s.strip.presence
      raise Error, "Google OAuth client id is not configured. Set GOOGLE_OAUTH_CLIENT_ID." if @client_id.blank?
      raise Error, "Google OAuth client secret is not configured. Set GOOGLE_OAUTH_CLIENT_SECRET." if @client_secret.blank?
    end

    def authorization_url(redirect_uri:, state:)
      uri = AUTHORIZATION_ENDPOINT.dup
      uri.query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: redirect_uri.to_s,
        response_type: "code",
        scope: CALENDAR_READONLY_SCOPE,
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: "true",
        state: state.to_s
      )
      uri.to_s
    rescue URI::InvalidURIError => error
      raise Error, "Google authorization URL could not be built: #{error.message}"
    end

    def exchange_code!(code:, redirect_uri:)
      code_value = code.to_s.strip
      raise Error, "Google authorization code missing." if code_value.blank?

      request = Net::HTTP::Post.new(TOKEN_ENDPOINT)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(
        code: code_value,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri.to_s,
        grant_type: "authorization_code"
      )

      response = Net::HTTP.start(
        TOKEN_ENDPOINT.host,
        TOKEN_ENDPOINT.port,
        use_ssl: true,
        open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
        read_timeout: REQUEST_TIMEOUT_SECONDS
      ) do |http|
        http.request(request)
      end

      status = response.code.to_i
      body = parse_json(response.body)
      access_token = body["access_token"].to_s.strip
      unless (200..299).cover?(status) && access_token.present?
        message = extract_error_message(body)
        raise Error, "Google token exchange failed (#{status}): #{message}"
      end

      {
        access_token: access_token,
        refresh_token: body["refresh_token"].to_s.strip.presence,
        scope: body["scope"].to_s,
        token_type: body["token_type"].to_s,
        expires_in: body["expires_in"].to_i
      }
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
      raise Error, "Google token exchange request failed: #{error.message}"
    end

    private

    attr_reader :client_id, :client_secret

    def parse_json(raw_body)
      body = raw_body.to_s
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def extract_error_message(body)
      error_value = body["error"]
      nested_error_message = error_value.is_a?(Hash) ? error_value["message"].to_s.presence : nil

      body["error_description"].to_s.presence ||
        nested_error_message ||
        error_value.to_s.presence ||
        "Unknown Google OAuth error"
    end
  end
end
