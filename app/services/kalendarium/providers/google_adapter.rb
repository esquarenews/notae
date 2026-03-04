require "cgi"
require "digest"
require "json"
require "net/http"
require "time"
require "uri"

module Kalendarium
  module Providers
    class GoogleAdapter < BaseAdapter
      def sync!(calendar: nil, range_start: nil, range_end: nil)
        ensure_credentials!
        effective_range_start, effective_range_end = sync_range(range_start:, range_end:)

        if calendar.present?
          ensure_calendar_belongs_to_connection!(calendar)
          sync_single_calendar(calendar, range_start: effective_range_start, range_end: effective_range_end)
        else
          sync_all_calendars(range_start: effective_range_start, range_end: effective_range_end)
        end

        true
      end

      def upsert_remote_event!(calendar:, event:)
        ensure_credentials!
        ensure_calendar_belongs_to_connection!(calendar)

        payload = build_google_event_write_payload(event: event, calendar: calendar)
        params = { conferenceDataVersion: 1, sendUpdates: "none" }
        remote_event = if event.remote_event_id.present?
          request_json(
            method: :patch,
            path: "/calendar/v3/calendars/#{CGI.escape(calendar.remote_id.to_s)}/events/#{CGI.escape(event.remote_event_id.to_s)}",
            params: params,
            body: payload
          )
        else
          request_json(
            method: :post,
            path: "/calendar/v3/calendars/#{CGI.escape(calendar.remote_id.to_s)}/events",
            params: params,
            body: payload
          )
        end

        apply_remote_event_response_to_local_event!(
          event: event,
          calendar: calendar,
          remote_event: remote_event
        )
      end

      def delete_remote_event!(calendar:, event:)
        ensure_credentials!
        ensure_calendar_belongs_to_connection!(calendar)
        return true if event.remote_event_id.blank?

        request_json(
          method: :delete,
          path: "/calendar/v3/calendars/#{CGI.escape(calendar.remote_id.to_s)}/events/#{CGI.escape(event.remote_event_id.to_s)}",
          params: { sendUpdates: "none" }
        )
        true
      rescue RuntimeError => error
        return true if error.message.include?("Google Calendar request failed (404)")

        raise
      end

      private

      GOOGLE_CALENDAR_API_BASE_URL = "https://www.googleapis.com".freeze
      GOOGLE_TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")
      DEFAULT_CALENDAR_COLOR = "#3B82F6".freeze
      LOOKBACK_DAYS = 365
      LOOKAHEAD_DAYS = 365
      REQUEST_TIMEOUT_SECONDS = 30
      REQUEST_OPEN_TIMEOUT_SECONDS = 10
      GOOGLE_EVENT_TYPES = %w[default outOfOffice focusTime workingLocation birthday fromGmail].freeze

      def sync_all_calendars(range_start:, range_end:)
        remote_calendars = fetch_all_remote_calendars
        synced_remote_ids = remote_calendars.map do |remote_calendar|
          local_calendar = upsert_remote_calendar(remote_calendar)
          sync_single_calendar(local_calendar, range_start: range_start, range_end: range_end)
          local_calendar.remote_id
        end

        disable_missing_provider_calendars(synced_remote_ids)
      end

      def sync_single_calendar(calendar, range_start:, range_end:)
        seen_remote_event_ids = []
        events = fetch_calendar_events(
          calendar_id: calendar.remote_id,
          range_start: range_start,
          range_end: range_end
        )

        events.each_with_index do |remote_event, index|
          remote_event_id = normalize_remote_event_id(event: remote_event, starts_at_utc: nil, index: index)
          next if remote_event_id.blank?

          status = normalize_status(remote_event["status"])
          starts_at_utc, starts_all_day = parse_google_time(remote_event["start"], fallback_time_zone: calendar.time_zone)
          if starts_at_utc.blank?
            if status == "cancelled"
              mark_cancelled_remote_event(calendar: calendar, remote_event_id: remote_event_id)
              seen_remote_event_ids << remote_event_id
            end
            next
          end

          ends_at_utc, ends_all_day = parse_google_time(remote_event["end"], fallback_time_zone: calendar.time_zone)
          ends_at_utc ||= starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
          if ends_at_utc <= starts_at_utc
            ends_at_utc = starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
          end

          remote_event_id = normalize_remote_event_id(event: remote_event, starts_at_utc: starts_at_utc, index: index)
          next if remote_event_id.blank?

          seen_remote_event_ids << remote_event_id
          upsert_remote_event(
            calendar: calendar,
            remote_event_id: remote_event_id,
            remote_event: remote_event,
            starts_at_utc: starts_at_utc,
            ends_at_utc: ends_at_utc,
            all_day: starts_all_day || ends_all_day
          )
        end

        cancel_stale_provider_events(calendar: calendar, seen_remote_event_ids: seen_remote_event_ids)
      end

      def ensure_credentials!
        return if connection.google_tokens_configured? && connection.access_token.present?
        return refresh_access_token! if connection.google_tokens_configured? && connection.refresh_token.present?

        raise "Google access token is missing or no longer decryptable. Re-authorize Google OAuth."
      end

      def ensure_calendar_belongs_to_connection!(calendar)
        return if calendar.kalendarium_connection_id == connection.id && calendar.remote_id.present?

        raise "Calendar does not belong to this Google connection"
      end

      def fetch_all_remote_calendars
        items = []
        page_token = nil

        loop do
          response = fetch_json(
            path: "/calendar/v3/users/me/calendarList",
            params: {
              maxResults: 250,
              showHidden: true,
              pageToken: page_token.presence
            }
          )
          items.concat(Array(response["items"]))
          page_token = response["nextPageToken"].to_s.presence
          break if page_token.blank?
        end

        items.reject { |calendar_item| ActiveModel::Type::Boolean.new.cast(calendar_item["deleted"]) }
      end

      def fetch_calendar_events(calendar_id:, range_start:, range_end:)
        items = []
        page_token = nil

        loop do
          response = fetch_json(
            path: "/calendar/v3/calendars/#{CGI.escape(calendar_id.to_s)}/events",
            params: {
              maxResults: 2500,
              orderBy: "startTime",
              singleEvents: true,
              showDeleted: true,
              alwaysIncludeEmail: true,
              conferenceDataVersion: 1,
              maxAttendees: 200,
              timeMin: range_start.utc.iso8601,
              timeMax: range_end.utc.iso8601,
              eventTypes: GOOGLE_EVENT_TYPES,
              pageToken: page_token.presence
            }
          )
          items.concat(Array(response["items"]))
          page_token = response["nextPageToken"].to_s.presence
          break if page_token.blank?
        end

        items
      end

      def sync_range(range_start:, range_end:)
        start_time = range_start.presence || (Time.current - LOOKBACK_DAYS.days).beginning_of_day
        end_time = range_end.presence || (Time.current + LOOKAHEAD_DAYS.days).end_of_day
        [ start_time, end_time ]
      end

      def upsert_remote_calendar(remote_calendar)
        remote_id = remote_calendar["id"].to_s
        calendar = connection.kalendarium_calendars.find_or_initialize_by(remote_id: remote_id)
        calendar.workspace = connection.workspace
        calendar.provider = connection.provider
        calendar.created_by ||= connection.created_by
        calendar.name = remote_calendar["summary"].to_s.presence || "Google calendar"
        calendar.color_hex = normalize_color_hex(remote_calendar["backgroundColor"])
        calendar.time_zone = normalize_time_zone_name(remote_calendar["timeZone"]) ||
                             normalize_time_zone_name(connection.created_by&.time_zone) ||
                             "UTC"
        calendar.read_only = read_only_access_role?(remote_calendar["accessRole"])
        calendar.source_kind = "provider"
        calendar.enabled = true if calendar.new_record?
        calendar.metadata_json = calendar.metadata_json.to_h.merge(
          "description" => remote_calendar["description"].to_s.presence,
          "etag" => remote_calendar["etag"].to_s.presence,
          "access_role" => remote_calendar["accessRole"].to_s.presence,
          "primary" => ActiveModel::Type::Boolean.new.cast(remote_calendar["primary"])
        ).compact
        calendar.save!
        calendar
      end

      def disable_missing_provider_calendars(synced_remote_ids)
        scope = connection.kalendarium_calendars.where(source_kind: "provider")
        scope = synced_remote_ids.any? ? scope.where.not(remote_id: synced_remote_ids) : scope
        scope.find_each do |calendar|
          next unless calendar.enabled?

          calendar.update!(enabled: false)
        end
      end

      def upsert_remote_event(calendar:, remote_event_id:, remote_event:, starts_at_utc:, ends_at_utc:, all_day:)
        event = calendar.kalendarium_events.find_or_initialize_by(remote_event_id: remote_event_id)
        invitees = extract_google_invitees(remote_event)
        meeting_join_url = extract_google_meeting_join_url(remote_event)
        event.workspace = connection.workspace
        event.created_by ||= connection.created_by
        event.updated_by = connection.created_by
        event.source_kind = "provider"
        event.uid = remote_event["iCalUID"].to_s.presence || remote_event["id"].to_s.presence || remote_event_id
        event.etag = remote_event["etag"].to_s.presence
        event.sequence = remote_event["sequence"].to_i
        event.title = truncate_text(google_event_title(remote_event), limit: 200, fallback: "(Untitled event)")
        event.description = remote_event["description"].to_s.presence
        event.location = remote_event["location"].to_s.presence
        event.starts_at_utc = starts_at_utc
        event.ends_at_utc = ends_at_utc
        event.all_day = all_day
        event.rrule = Array(nested_value(remote_event, "recurrence")).first.to_s.presence
        event.status = normalize_status(remote_event["status"])
        event.visibility = normalize_visibility(remote_event["visibility"])
        event.last_synced_at = Time.current
        event.metadata_json = event.metadata_json.to_h.merge(
          "html_link" => remote_event["htmlLink"].to_s.presence,
          "creator_email" => nested_value(remote_event, "creator", "email").to_s.presence,
          "organizer_email" => nested_value(remote_event, "organizer", "email").to_s.presence,
          "recurring_event_id" => remote_event["recurringEventId"].to_s.presence,
          "event_type" => remote_event["eventType"].to_s.presence,
          "original_start_time" => nested_value(remote_event, "originalStartTime", "dateTime").to_s.presence || nested_value(remote_event, "originalStartTime", "date").to_s.presence,
          "meeting_join_url" => meeting_join_url,
          "invitees" => invitees.presence,
          "provider" => connection.provider
        ).compact
        event.save!
      end

      def build_google_event_write_payload(event:, calendar:)
        payload = {
          "summary" => event.title.to_s.strip.presence || "(Untitled event)",
          "description" => event.description.to_s.presence,
          "location" => event.location.to_s.presence
        }.compact

        if event.all_day?
          starts_local = event.starts_at_utc.in_time_zone(calendar.time_zone)
          ends_local = event.ends_at_utc.in_time_zone(calendar.time_zone)
          end_date = ends_local.to_date
          end_date = starts_local.to_date + 1.day if end_date <= starts_local.to_date
          payload["start"] = { "date" => starts_local.to_date.iso8601 }
          payload["end"] = { "date" => end_date.iso8601 }
        else
          payload["start"] = {
            "dateTime" => event.starts_at_utc.utc.iso8601,
            "timeZone" => "UTC"
          }
          payload["end"] = {
            "dateTime" => event.ends_at_utc.utc.iso8601,
            "timeZone" => "UTC"
          }
        end

        if event.rrule.present?
          payload["recurrence"] = [ event.rrule.to_s ]
        end

        reminder_offsets = Array(event.reminder_offsets_minutes).map(&:to_i).select { |offset| offset >= 0 }.uniq.sort
        if reminder_offsets.any?
          payload["reminders"] = {
            "useDefault" => false,
            "overrides" => reminder_offsets.map { |offset| { "method" => "popup", "minutes" => offset } }
          }
        end

        if %w[public private].include?(event.visibility)
          payload["visibility"] = event.visibility
        end

        payload
      end

      def apply_remote_event_response_to_local_event!(event:, calendar:, remote_event:)
        remote_event_id = remote_event["id"].to_s.strip.presence || event.remote_event_id
        starts_at_utc, starts_all_day = parse_google_time(remote_event["start"], fallback_time_zone: calendar.time_zone)
        ends_at_utc, ends_all_day = parse_google_time(remote_event["end"], fallback_time_zone: calendar.time_zone)
        ends_at_utc ||= starts_all_day ? starts_at_utc&.+(1.day) : starts_at_utc&.+(1.hour)
        if starts_at_utc.present? && ends_at_utc.present? && ends_at_utc <= starts_at_utc
          ends_at_utc = starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
        end

        event.remote_event_id = remote_event_id
        event.uid = remote_event["iCalUID"].to_s.presence || event.uid
        event.etag = remote_event["etag"].to_s.presence || event.etag
        event.sequence = remote_event["sequence"].to_i if remote_event["sequence"].present?
        event.starts_at_utc = starts_at_utc if starts_at_utc.present?
        event.ends_at_utc = ends_at_utc if ends_at_utc.present?
        event.all_day = starts_all_day || ends_all_day if remote_event["start"].present? || remote_event["end"].present?
        event.status = normalize_status(remote_event["status"]) if remote_event["status"].present?
        event.visibility = normalize_visibility(remote_event["visibility"]) if remote_event["visibility"].present?
        event.source_kind = "provider"
        event.last_synced_at = Time.current
        event.metadata_json = event.metadata_json.to_h.merge(
          "html_link" => remote_event["htmlLink"].to_s.presence,
          "creator_email" => nested_value(remote_event, "creator", "email").to_s.presence,
          "organizer_email" => nested_value(remote_event, "organizer", "email").to_s.presence,
          "recurring_event_id" => remote_event["recurringEventId"].to_s.presence,
          "event_type" => remote_event["eventType"].to_s.presence,
          "original_start_time" => nested_value(remote_event, "originalStartTime", "dateTime").to_s.presence || nested_value(remote_event, "originalStartTime", "date").to_s.presence,
          "meeting_join_url" => extract_google_meeting_join_url(remote_event),
          "invitees" => extract_google_invitees(remote_event).presence,
          "provider" => connection.provider
        ).compact
        event.save!
        event
      end

      def google_event_title(remote_event)
        summary = remote_event["summary"].to_s.strip
        return summary if summary.present?

        event_type = remote_event["eventType"].to_s.strip
        return "Working location#{working_location_suffix(remote_event)}" if event_type == "workingLocation"

        "(Untitled event)"
      end

      def working_location_suffix(remote_event)
        properties = remote_event["workingLocationProperties"].to_h
        location_type = properties["type"].to_s.strip

        label =
          case location_type
          when "homeOffice"
            "Home"
          when "officeLocation"
            properties.dig("officeLocation", "label").to_s.strip.presence ||
              properties.dig("officeLocation", "buildingId").to_s.strip.presence ||
              "Office"
          when "customLocation"
            properties.dig("customLocation", "label").to_s.strip.presence ||
              properties.dig("customLocation", "address").to_s.strip.presence ||
              "Custom"
          else
            nil
          end

        label.present? ? ": #{label}" : ""
      end

      def mark_cancelled_remote_event(calendar:, remote_event_id:)
        event = calendar.kalendarium_events.find_by(remote_event_id: remote_event_id)
        return if event.blank? || event.status == "cancelled"

        event.update!(
          status: "cancelled",
          updated_by: connection.created_by,
          last_synced_at: Time.current
        )
      end

      def cancel_stale_provider_events(calendar:, seen_remote_event_ids:)
        scope = calendar.kalendarium_events.where(source_kind: "provider")
        scope = seen_remote_event_ids.any? ? scope.where.not(remote_event_id: seen_remote_event_ids) : scope
        scope.find_each do |event|
          next if event.status == "cancelled"

          event.update!(
            status: "cancelled",
            updated_by: connection.created_by,
            last_synced_at: Time.current
          )
        end
      end

      def parse_google_time(entry, fallback_time_zone:)
        data = entry.to_h
        date_value = data["date"].to_s.strip
        if date_value.present?
          date = Date.iso8601(date_value)
          return [ date.beginning_of_day.utc, true ]
        end

        date_time_value = data["dateTime"].to_s.strip
        return [ nil, false ] if date_time_value.blank?

        if date_time_value.match?(/(Z|[+-]\d{2}:\d{2})\z/)
          return [ Time.iso8601(date_time_value).utc, false ]
        end

        zone = resolve_time_zone(data["timeZone"], fallback_time_zone: fallback_time_zone)
        [ zone.parse(date_time_value)&.utc, false ]
      rescue ArgumentError, TypeError
        [ nil, false ]
      end

      def resolve_time_zone(raw_time_zone, fallback_time_zone:)
        candidates = []
        time_zone = raw_time_zone.to_s.strip
        fallback = fallback_time_zone.to_s.strip
        candidates << time_zone if time_zone.present?
        candidates << fallback if fallback.present?
        candidates << "UTC"
        candidates.each do |candidate|
          zone = ActiveSupport::TimeZone[candidate]
          return zone if zone.present?
        end

        ActiveSupport::TimeZone["UTC"]
      end

      def normalize_remote_event_id(event:, starts_at_utc:, index:)
        event_id = event["id"].to_s.strip
        recurring_event_id = event["recurringEventId"].to_s.strip
        original_start = nested_value(event, "originalStartTime", "dateTime").to_s.strip
        original_start = nested_value(event, "originalStartTime", "date").to_s.strip if original_start.blank?
        starts_at_value = starts_at_utc&.utc&.iso8601(6).to_s

        stable_id =
          if event_id.present?
            event_id
          elsif recurring_event_id.present? && original_start.present?
            "#{recurring_event_id}::#{original_start}"
          elsif recurring_event_id.present? && starts_at_value.present?
            "#{recurring_event_id}::#{starts_at_value}"
          elsif starts_at_value.present?
            "google-event-#{starts_at_value}"
          else
            "google-event-#{index}"
          end

        stable_id.length > 240 ? Digest::SHA256.hexdigest(stable_id) : stable_id
      end

      def fetch_json(path:, params:, allow_refresh: true)
        request_json(method: :get, path: path, params: params, allow_refresh: allow_refresh)
      end

      def request_json(method:, path:, params: {}, body: nil, allow_refresh: true)
        uri = build_api_uri(path: path, params: params)
        response = if method.to_s.downcase == "get"
          perform_api_get(uri: uri, access_token: connection.access_token)
        else
          perform_api_request(uri: uri, access_token: connection.access_token, method: method, body: body)
        end
        status = response.code.to_i
        parsed_body = parse_json(response.body)
        return parsed_body if (200..299).cover?(status)

        if status == 401
          if allow_refresh && connection.google_tokens_configured? && connection.refresh_token.present?
            refresh_access_token!
            return request_json(method: method, path: path, params: params, body: body, allow_refresh: false)
          end

          raise "Google authentication failed (401). Reconnect Google once to restore refresh tokens."
        end

        message = extract_api_error_message(parsed_body)
        if status == 403
          if insufficient_permissions_error?(message: message)
            raise "Google calendar write permission is missing for this connection. Re-authorize Google with calendar write access."
          end

          if allow_refresh && connection.google_tokens_configured? && connection.refresh_token.present?
            refresh_access_token!
            return request_json(method: method, path: path, params: params, body: body, allow_refresh: false)
          end

          raise "Google authentication failed (403). Reconnect Google once to restore refresh tokens."
        end

        raise "Google Calendar request failed (#{status}): #{message}"
      end

      def build_api_uri(path:, params:)
        uri = URI.join(GOOGLE_CALENDAR_API_BASE_URL, path)
        query_pairs = build_query_pairs(params)
        uri.query = URI.encode_www_form(query_pairs) if query_pairs.any?
        uri
      rescue URI::InvalidURIError
        raise "Google Calendar request URI is invalid"
      end

      def build_query_pairs(params)
        params.to_h.each_with_object([]) do |(key, raw_value), pairs|
          values = raw_value.is_a?(Array) ? raw_value : [ raw_value ]
          values.each do |value|
            next if value.nil?

            text_value = value.to_s
            next if text_value.blank?

            pairs << [ key.to_s, text_value ]
          end
        end
      end

      def perform_api_get(uri:, access_token:)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google Calendar request failed: #{error.message}"
      end

      def perform_api_request(uri:, access_token:, method:, body: nil)
        request_class = case method.to_s.downcase.to_sym
        when :post
          Net::HTTP::Post
        when :put
          Net::HTTP::Put
        when :patch
          Net::HTTP::Patch
        when :delete
          Net::HTTP::Delete
        else
          raise ArgumentError, "Unsupported HTTP method for Google request: #{method}"
        end

        request = request_class.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"
        if body.present?
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google Calendar request failed: #{error.message}"
      end

      def parse_json(raw_body)
        body = raw_body.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      def extract_api_error_message(body)
        nested_value(body, "error", "message").to_s.presence || body.to_h["error_description"].to_s.presence || "Unknown API error"
      end

      def refresh_access_token!
        credential_candidates = refresh_token_credential_candidates
        if credential_candidates.empty?
          raise "Google token refresh requires GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET."
        end

        last_error_message = nil
        credential_candidates.each do |candidate|
          response = perform_token_refresh_request(
            client_id: candidate.fetch(:client_id),
            client_secret: candidate.fetch(:client_secret)
          )
          status = response.code.to_i
          body = parse_json(response.body)
          access_token = body["access_token"].to_s.strip

          if (200..299).cover?(status) && access_token.present?
            persist_refreshed_tokens!(body)
            persist_oauth_client_credentials!(
              client_id: candidate.fetch(:client_id),
              client_secret: candidate.fetch(:client_secret)
            )
            return
          end

          message = extract_api_error_message(body)
          last_error_message = "Google token refresh failed (#{status}): #{message}"
          next if invalid_client_error?(status: status, message: message)

          raise last_error_message
        end

        raise(last_error_message || "Google token refresh failed.")
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google token refresh failed: #{error.message}"
      end

      def perform_token_refresh_request(client_id:, client_secret:)
        request = Net::HTTP::Post.new(GOOGLE_TOKEN_ENDPOINT)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: connection.refresh_token,
          grant_type: "refresh_token"
        )

        Net::HTTP.start(
          GOOGLE_TOKEN_ENDPOINT.host,
          GOOGLE_TOKEN_ENDPOINT.port,
          use_ssl: true,
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      end

      def refresh_token_credential_candidates
        candidates = []
        if connection.oauth_client_id.present? && connection.oauth_client_secret.present?
          candidates << {
            client_id: connection.oauth_client_id.to_s.strip,
            client_secret: connection.oauth_client_secret.to_s.strip
          }
        end

        fallback_client_id = fallback_google_client_id
        fallback_client_secret = fallback_google_client_secret
        if fallback_client_id.present? && fallback_client_secret.present?
          candidates << { client_id: fallback_client_id, client_secret: fallback_client_secret }
        end

        candidates.uniq
      end

      def invalid_client_error?(status:, message:)
        return false unless [ 400, 401 ].include?(status)

        lowered = message.to_s.downcase
        lowered.include?("invalid_client") || lowered.include?("oauth client was not found")
      end

      def insufficient_permissions_error?(message:)
        lowered = message.to_s.downcase
        lowered.include?("insufficient permissions") ||
          lowered.include?("insufficientpermission") ||
          lowered.include?("calendar write permission") ||
          lowered.include?("not allowed for this calendar")
      end

      def persist_oauth_client_credentials!(client_id:, client_secret:)
        return if client_id.blank? || client_secret.blank?
        return if connection.oauth_client_id == client_id && connection.oauth_client_secret == client_secret

        connection.update_columns(
          oauth_client_id: client_id,
          oauth_client_secret: client_secret,
          updated_at: Time.current
        )
      end

      def persist_refreshed_tokens!(token_body)
        connection.access_token = token_body["access_token"].to_s.strip.presence
        refreshed_token = token_body["refresh_token"].to_s.strip
        connection.refresh_token = refreshed_token if refreshed_token.present?

        scope_values = token_body["scope"].to_s.split(/\s+/).reject(&:blank?)
        connection.scopes_json = scope_values if scope_values.any?

        settings = connection.settings_json.to_h
        if token_body["expires_in"].present?
          expires_at = Time.current + token_body["expires_in"].to_i.seconds
          settings["google_access_token_expires_at"] = expires_at.iso8601
        end
        settings["google_token_type"] = token_body["token_type"].to_s if token_body["token_type"].present?
        connection.settings_json = settings.compact
        connection.save!
      end

      def google_client_id
        connection.oauth_client_id.to_s.presence ||
          fallback_google_client_id
      end

      def google_client_secret
        connection.oauth_client_secret.to_s.presence ||
          fallback_google_client_secret
      end

      def fallback_google_client_id
        ENV["GOOGLE_OAUTH_CLIENT_ID"].to_s.presence ||
          ENV["GOOGLE_CLIENT_ID"].to_s.presence ||
          oauth_credentials_value(
            %i[google oauth_client_id],
            %i[google_oauth client_id],
            %i[google_oauth_client_id],
            [ "GOOGLE_OAUTH_CLIENT_ID" ]
          ) ||
          connection.settings_json.to_h["google_client_id"].to_s.presence
      end

      def fallback_google_client_secret
        ENV["GOOGLE_OAUTH_CLIENT_SECRET"].to_s.presence ||
          ENV["GOOGLE_CLIENT_SECRET"].to_s.presence ||
          oauth_credentials_value(
            %i[google oauth_client_secret],
            %i[google_oauth client_secret],
            %i[google_oauth_client_secret],
            [ "GOOGLE_OAUTH_CLIENT_SECRET" ]
          ) ||
          connection.settings_json.to_h["google_client_secret"].to_s.presence
      end

      def oauth_credentials_value(*dig_paths)
        credentials = Rails.application.credentials

        dig_paths.each do |path|
          candidate_paths = [
            Array(path),
            Array(path).map(&:to_sym),
            Array(path).map(&:to_s)
          ].uniq

          candidate_paths.each do |candidate|
            value = if candidate.length == 1
              credentials[candidate.first]
            else
              nested_value(credentials, *candidate)
            end
            normalized = value.to_s.strip
            return normalized if normalized.present?
          end
        end

        nil
      rescue StandardError
        nil
      end

      def read_only_access_role?(access_role)
        !%w[owner writer].include?(access_role.to_s.downcase)
      end

      def normalize_color_hex(raw_color)
        value = raw_color.to_s.strip
        return DEFAULT_CALENDAR_COLOR if value.blank?

        hex = value.delete_prefix("#")[0, 6]
        return "##{hex.upcase}" if hex.match?(/\A[0-9A-Fa-f]{6}\z/)

        DEFAULT_CALENDAR_COLOR
      end

      def normalize_time_zone_name(raw_time_zone)
        value = raw_time_zone.to_s.strip
        return nil if value.blank?
        return value if ActiveSupport::TimeZone[value].present?

        normalized = value.split("/").last
        return normalized if ActiveSupport::TimeZone[normalized].present?

        nil
      end

      def normalize_status(raw_status)
        value = raw_status.to_s.downcase
        return "cancelled" if value == "cancelled"
        return "tentative" if value == "tentative"

        "confirmed"
      end

      def normalize_visibility(raw_visibility)
        value = raw_visibility.to_s.downcase
        return "public" if value == "public"
        return "private" if value == "private"

        "default"
      end

      def truncate_text(raw_value, limit:, fallback:)
        value = raw_value.to_s.strip
        value = fallback if value.blank?
        value.length > limit ? "#{value[0, limit - 3]}..." : value
      end

      def extract_google_invitees(remote_event)
        Array(remote_event["attendees"]).filter_map do |attendee|
          next unless attendee.is_a?(Hash)

          email = attendee["email"].to_s.strip.presence
          name = attendee["displayName"].to_s.strip.presence
          status = attendee["responseStatus"].to_s.strip.presence
          next if email.blank? && name.blank?

          {
            "email" => email,
            "name" => name,
            "status" => status
          }.compact
        end
      end

      def extract_google_meeting_join_url(remote_event)
        candidates = []
        conference_entry_points = Array(nested_value(remote_event, "conferenceData", "entryPoints"))
        video_entry_points = conference_entry_points.select { |entry| entry.to_h["entryPointType"].to_s == "video" }
        (video_entry_points + conference_entry_points).each do |entry|
          candidates << entry.to_h["uri"].to_s
        end
        candidates << remote_event["hangoutLink"].to_s
        candidates << first_url_in_text(remote_event["location"])
        candidates << first_url_in_text(remote_event["description"])

        candidates.filter_map { |value| normalized_http_url(value) }.first
      end

      def first_url_in_text(value)
        value.to_s[%r{https?://[^\s<>()]+}]
      end

      def normalized_http_url(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        uri = URI.parse(raw)
        return nil unless uri.is_a?(URI::HTTP)
        return nil if uri.host.blank?

        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def nested_value(source, *keys)
        keys.reduce(source) do |current, key|
          break nil unless current.respond_to?(:[])

          if current.is_a?(Hash)
            current[key] || current[key.to_s] || current[key.to_sym]
          else
            current[key]
          end
        end
      rescue StandardError
        nil
      end
    end
  end
end
