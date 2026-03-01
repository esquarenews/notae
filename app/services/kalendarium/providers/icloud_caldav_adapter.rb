require "base64"
require "digest"
require "net/http"
require "rexml/document"
require "time"
require "uri"

module Kalendarium
  module Providers
    class IcloudCaldavAdapter < BaseAdapter
      XML_NS = {
        "d" => "DAV:",
        "c" => "urn:ietf:params:xml:ns:caldav",
        "cs" => "http://calendarserver.org/ns/",
        "apple" => "http://apple.com/ns/ical/"
      }.freeze
      DEFAULT_ICAL_COLOR = "#3B82F6".freeze
      ICLOUD_CALDAV_BASE_URL = "https://caldav.icloud.com".freeze
      LOOKBACK_DAYS = 365
      LOOKAHEAD_DAYS = 365
      REQUEST_TIMEOUT_SECONDS = 30
      REQUEST_OPEN_TIMEOUT_SECONDS = 10
      MAX_REDIRECTS = 3

      def sync!(calendar: nil)
        ensure_credentials!

        if calendar.present?
          ensure_calendar_belongs_to_connection!(calendar)
          sync_single_calendar(calendar)
        else
          sync_all_calendars
        end

        true
      end

      private

      def sync_all_calendars
        principal_href = fetch_current_user_principal_href
        home_href = fetch_calendar_home_href(principal_href)
        remote_calendars = fetch_remote_calendars(home_href)

        synced_remote_ids = remote_calendars.map do |remote_calendar|
          local_calendar = upsert_remote_calendar(remote_calendar)
          sync_single_calendar(local_calendar)
          local_calendar.remote_id
        end

        disable_missing_provider_calendars(synced_remote_ids)
      end

      def sync_single_calendar(calendar)
        payloads = fetch_calendar_event_payloads(
          calendar.remote_id,
          range_start: (Time.current - LOOKBACK_DAYS.days).beginning_of_day,
          range_end: (Time.current + LOOKAHEAD_DAYS.days).end_of_day
        )

        seen_remote_event_ids = []
        payloads.each do |payload|
          parse_ical_events(payload[:calendar_data], fallback_time_zone: calendar.time_zone).each_with_index do |event_payload, index|
            remote_event_id = normalize_remote_event_id(
              remote_href: payload[:href],
              uid: event_payload[:uid],
              recurrence_id: event_payload[:recurrence_id],
              starts_at_utc: event_payload[:starts_at_utc],
              index: index
            )
            next if remote_event_id.blank? || event_payload[:starts_at_utc].blank?

            seen_remote_event_ids << remote_event_id
            upsert_remote_event(
              calendar: calendar,
              remote_event_id: remote_event_id,
              remote_href: payload[:href],
              etag: payload[:etag],
              event_payload: event_payload
            )
          end
        end

        cancel_stale_provider_events(calendar: calendar, seen_remote_event_ids: seen_remote_event_ids)
      end

      def ensure_credentials!
        return if connection.provider_username.present? && connection.provider_password.present?

        raise "iCloud CalDAV credentials are missing"
      end

      def ensure_calendar_belongs_to_connection!(calendar)
        return if calendar.kalendarium_connection_id == connection.id && calendar.remote_id.present?

        raise "Calendar does not belong to this iCloud connection"
      end

      def fetch_current_user_principal_href
        body = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <d:propfind xmlns:d="DAV:">
            <d:prop>
              <d:current-user-principal />
              <d:principal-URL />
            </d:prop>
          </d:propfind>
        XML

        responses = propfind("/", body: body, depth: "0")
        responses.each do |response|
          prop = successful_prop(response)
          next if prop.blank?

          principal = text_at(prop, "d:current-user-principal/d:href") || text_at(prop, "d:principal-URL/d:href")
          return normalize_href(principal) if principal.present?
        end

        raise "Unable to discover iCloud CalDAV principal URL"
      end

      def fetch_calendar_home_href(principal_href)
        body = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
            <d:prop>
              <c:calendar-home-set />
            </d:prop>
          </d:propfind>
        XML

        responses = propfind(principal_href, body: body, depth: "0")
        responses.each do |response|
          prop = successful_prop(response)
          next if prop.blank?

          home_href = text_at(prop, "c:calendar-home-set/d:href")
          return normalize_href(home_href) if home_href.present?
        end

        raise "Unable to discover iCloud CalDAV calendar home"
      end

      def fetch_remote_calendars(home_href)
        body = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:apple="http://apple.com/ns/ical/">
            <d:prop>
              <d:resourcetype />
              <d:displayname />
              <apple:calendar-color />
              <c:calendar-timezone />
              <cs:getctag />
            </d:prop>
          </d:propfind>
        XML

        propfind(home_href, body: body, depth: "1").filter_map do |response|
          prop = successful_prop(response)
          next if prop.blank?

          resource = calendar_resource_type(prop)
          next unless resource[:calendar] || resource[:subscribed]

          href = normalize_href(text_at(response, "d:href"))
          next if href.blank?

          {
            href: href,
            name: text_at(prop, "d:displayname"),
            color_hex: text_at(prop, "apple:calendar-color"),
            ctag: text_at(prop, "cs:getctag"),
            time_zone_hint: extract_calendar_time_zone_hint(text_at(prop, "c:calendar-timezone")),
            subscribed: resource[:subscribed]
          }
        end
      end

      def fetch_calendar_event_payloads(calendar_href, range_start:, range_end:)
        range_start_utc = range_start.utc.strftime("%Y%m%dT%H%M%SZ")
        range_end_utc = range_end.utc.strftime("%Y%m%dT%H%M%SZ")
        body = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
            <d:prop>
              <d:getetag />
              <c:calendar-data>
                <c:comp name="VCALENDAR">
                  <c:comp name="VEVENT">
                    <c:expand start="#{range_start_utc}" end="#{range_end_utc}" />
                    <c:prop name="UID" />
                    <c:prop name="SUMMARY" />
                    <c:prop name="DESCRIPTION" />
                    <c:prop name="LOCATION" />
                    <c:prop name="DTSTART" />
                    <c:prop name="DTEND" />
                    <c:prop name="DURATION" />
                    <c:prop name="STATUS" />
                    <c:prop name="SEQUENCE" />
                    <c:prop name="CLASS" />
                    <c:prop name="RECURRENCE-ID" />
                    <c:prop name="RRULE" />
                  </c:comp>
                </c:comp>
              </c:calendar-data>
            </d:prop>
            <c:filter>
              <c:comp-filter name="VCALENDAR">
                <c:comp-filter name="VEVENT">
                  <c:time-range start="#{range_start_utc}" end="#{range_end_utc}" />
                </c:comp-filter>
              </c:comp-filter>
            </c:filter>
          </c:calendar-query>
        XML

        report(calendar_href, body: body, depth: "1").filter_map do |response|
          prop = successful_prop(response)
          next if prop.blank?

          calendar_data = text_at(prop, "c:calendar-data")
          next if calendar_data.blank?

          {
            href: normalize_href(text_at(response, "d:href")),
            etag: text_at(prop, "d:getetag"),
            calendar_data: calendar_data
          }
        end
      end

      def upsert_remote_calendar(remote_calendar)
        calendar = connection.kalendarium_calendars.find_or_initialize_by(remote_id: remote_calendar[:href])
        time_zone_name = normalize_time_zone_name(remote_calendar[:time_zone_hint]) || normalize_time_zone_name(connection.created_by&.time_zone) || "UTC"

        calendar.workspace = connection.workspace
        calendar.provider = connection.provider
        calendar.created_by ||= connection.created_by
        calendar.name = remote_calendar[:name].presence || "iCloud calendar"
        calendar.color_hex = normalize_color_hex(remote_calendar[:color_hex])
        calendar.time_zone = time_zone_name
        calendar.read_only = true
        calendar.source_kind = "provider"
        calendar.enabled = true if calendar.new_record?
        calendar.metadata_json = calendar.metadata_json.to_h.merge(
          "ctag" => remote_calendar[:ctag].to_s.presence,
          "subscribed" => remote_calendar[:subscribed]
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

      def upsert_remote_event(calendar:, remote_event_id:, remote_href:, etag:, event_payload:)
        event = calendar.kalendarium_events.find_or_initialize_by(remote_event_id: remote_event_id)
        event.workspace = connection.workspace
        event.created_by ||= connection.created_by
        event.updated_by = connection.created_by
        event.source_kind = "provider"
        event.uid = event_payload[:uid].to_s.presence
        event.etag = etag.to_s.presence
        event.sequence = event_payload[:sequence].to_i
        event.title = truncate_text(event_payload[:title], limit: 200, fallback: "(Untitled event)")
        event.description = event_payload[:description].to_s.presence
        event.location = event_payload[:location].to_s.presence
        event.starts_at_utc = event_payload[:starts_at_utc]
        event.ends_at_utc = event_payload[:ends_at_utc]
        event.all_day = event_payload[:all_day]
        event.rrule = event_payload[:rrule].to_s.presence
        event.status = normalize_status(event_payload[:status])
        event.visibility = normalize_visibility(event_payload[:visibility])
        event.last_synced_at = Time.current
        event.metadata_json = event.metadata_json.to_h.merge(
          "remote_href" => remote_href.to_s.presence,
          "provider" => connection.provider
        ).compact
        event.save!
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

      def parse_ical_events(calendar_data, fallback_time_zone:)
        rows = unfold_ical_lines(calendar_data)
        events = []
        current_fields = nil

        rows.each do |row|
          case row
          when "BEGIN:VEVENT"
            current_fields = {}
          when "END:VEVENT"
            parsed = build_ical_event_payload(current_fields, fallback_time_zone: fallback_time_zone)
            events << parsed if parsed.present?
            current_fields = nil
          else
            next if current_fields.nil?

            key, params, value = parse_ical_line(row)
            next if key.blank?

            current_fields[key] ||= []
            current_fields[key] << { value: value, params: params }
          end
        end

        events
      end

      def unfold_ical_lines(calendar_data)
        lines = []
        calendar_data.to_s.split(/\r\n|\n|\r/).each do |line|
          if (line.start_with?(" ") || line.start_with?("\t")) && lines.any?
            lines[-1] << line[1..]
          else
            lines << line
          end
        end
        lines
      end

      def parse_ical_line(row)
        name_and_params, value = row.split(":", 2)
        return [ nil, {}, nil ] if name_and_params.blank? || value.nil?

        key, *raw_params = name_and_params.split(";")
        params = raw_params.each_with_object({}) do |raw_param, acc|
          param_key, param_value = raw_param.split("=", 2)
          next if param_key.blank?

          acc[param_key.upcase] = param_value.to_s.gsub(/\A"|"\z/, "")
        end

        [ key.to_s.upcase, params, value ]
      end

      def build_ical_event_payload(fields, fallback_time_zone:)
        return nil if fields.blank?

        start_entry = first_field(fields, "DTSTART")
        starts_at_utc, starts_all_day = parse_ical_time(start_entry, fallback_time_zone: fallback_time_zone)
        return nil if starts_at_utc.blank?

        end_entry = first_field(fields, "DTEND")
        ends_at_utc, ends_all_day = parse_ical_time(end_entry, fallback_time_zone: fallback_time_zone)
        ends_at_utc ||= starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
        ends_at_utc = starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour if ends_at_utc <= starts_at_utc

        recurrence_entry = first_field(fields, "RECURRENCE-ID")
        recurrence_time, = parse_ical_time(recurrence_entry, fallback_time_zone: fallback_time_zone)

        {
          uid: field_value(fields, "UID"),
          recurrence_id: recurrence_time&.utc&.iso8601(6),
          title: field_value(fields, "SUMMARY"),
          description: field_value(fields, "DESCRIPTION"),
          location: field_value(fields, "LOCATION"),
          starts_at_utc: starts_at_utc,
          ends_at_utc: ends_at_utc,
          all_day: starts_all_day || ends_all_day,
          rrule: field_value(fields, "RRULE"),
          sequence: field_value(fields, "SEQUENCE").to_i,
          status: field_value(fields, "STATUS"),
          visibility: field_value(fields, "CLASS")
        }
      end

      def parse_ical_time(field_entry, fallback_time_zone:)
        return [ nil, false ] if field_entry.blank?

        raw_value = field_entry[:value].to_s.strip
        params = field_entry[:params].to_h
        return [ nil, false ] if raw_value.blank?

        value_type = params["VALUE"].to_s.upcase
        if value_type == "DATE" || raw_value.match?(/\A\d{8}\z/)
          date = Date.strptime(raw_value[0, 8], "%Y%m%d")
          return [ date.beginning_of_day.utc, true ]
        end

        if raw_value.match?(/\A\d{8}T\d{6}Z\z/)
          year = raw_value[0, 4].to_i
          month = raw_value[4, 2].to_i
          day = raw_value[6, 2].to_i
          hour = raw_value[9, 2].to_i
          minute = raw_value[11, 2].to_i
          second = raw_value[13, 2].to_i
          return [ Time.utc(year, month, day, hour, minute, second), false ]
        end

        if raw_value.match?(/\A\d{8}T\d{6}\z/)
          tz = resolve_time_zone(params["TZID"], fallback_time_zone: fallback_time_zone)
          local_time = tz.strptime(raw_value, "%Y%m%dT%H%M%S")
          return [ local_time.utc, false ]
        end

        parsed = Time.zone.parse(raw_value)
        [ parsed&.utc, false ]
      rescue ArgumentError, TypeError
        [ nil, false ]
      end

      def resolve_time_zone(raw_tzid, fallback_time_zone:)
        candidates = []
        raw_value = raw_tzid.to_s.strip
        candidates << raw_value if raw_value.present?
        candidates << raw_value.split("/").last if raw_value.include?("/")
        candidates << normalize_time_zone_name(fallback_time_zone)
        candidates.compact.uniq.each do |candidate|
          zone = ActiveSupport::TimeZone[candidate]
          return zone if zone.present?
        end

        ActiveSupport::TimeZone["UTC"]
      end

      def normalize_remote_event_id(remote_href:, uid:, recurrence_id:, starts_at_utc:, index:)
        uid_value = uid.to_s.strip
        recurrence_value = recurrence_id.to_s.strip
        starts_at_value = starts_at_utc&.utc&.iso8601(6).to_s
        href_value = remote_href.to_s.strip

        stable_id =
          if uid_value.present?
            if recurrence_value.present?
              "#{uid_value}::#{recurrence_value}"
            elsif starts_at_value.present?
              "#{uid_value}::#{starts_at_value}"
            else
              uid_value
            end
          elsif href_value.present?
            "#{href_value}##{index}"
          else
            "caldav-event-#{index}"
          end

        stable_id.length > 240 ? Digest::SHA256.hexdigest(stable_id) : stable_id
      end

      def normalize_color_hex(raw_color)
        value = raw_color.to_s.strip
        return DEFAULT_ICAL_COLOR if value.blank?

        hex = value.delete_prefix("#")
        hex = hex[0, 6]
        return "##{hex.upcase}" if hex.match?(/\A[0-9A-Fa-f]{6}\z/)

        DEFAULT_ICAL_COLOR
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
        return "private" if %w[private confidential].include?(value)

        "default"
      end

      def truncate_text(raw_value, limit:, fallback:)
        value = raw_value.to_s.strip
        value = fallback if value.blank?
        value.length > limit ? "#{value[0, limit - 3]}..." : value
      end

      def extract_calendar_time_zone_hint(raw_value)
        value = raw_value.to_s
        tzid_line = value.lines.find { |line| line.start_with?("TZID:") }
        tzid_line&.split(":", 2)&.last&.strip.presence || value.strip.presence
      end

      def first_field(fields, key)
        Array(fields[key]).first
      end

      def field_value(fields, key)
        first_field(fields, key).to_h[:value].to_s.presence
      end

      def propfind(href, body:, depth:)
        request_multistatus(method: "PROPFIND", href: href, body: body, depth: depth)
      end

      def report(href, body:, depth:)
        request_multistatus(method: "REPORT", href: href, body: body, depth: depth)
      end

      def request_multistatus(method:, href:, body:, depth:)
        xml_body = perform_xml_request(method: method, href: href, body: body, depth: depth)
        document = REXML::Document.new(xml_body)
        REXML::XPath.match(document, "//d:response", XML_NS)
      rescue REXML::ParseException => error
        raise "CalDAV response was not valid XML: #{error.message}"
      end

      def perform_xml_request(method:, href:, body:, depth:)
        uri = build_uri(href)
        response = perform_request(method: method, uri: uri, body: body, depth: depth, redirects: 0)
        status = response.code.to_i
        return response.body.to_s if status == 207 || (200..299).cover?(status)
        if [ 401, 403 ].include?(status)
          raise "CalDAV authentication failed (#{status}). Use Apple ID email and an app-specific password."
        end

        raise "CalDAV request failed (#{status})"
      end

      def perform_request(method:, uri:, body:, depth:, redirects:)
        raise "CalDAV request redirected too many times" if redirects > MAX_REDIRECTS

        headers = {
          "Authorization" => "Basic #{Base64.strict_encode64("#{connection.provider_username}:#{connection.provider_password}")}",
          "Content-Type" => "application/xml; charset=utf-8",
          "Accept" => "application/xml, text/xml, */*"
        }
        headers["Depth"] = depth if depth.present?

        request = Net::HTTPGenericRequest.new(method, body.present?, true, uri.request_uri.presence || "/", headers)
        request.body = body if body.present?

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end

        if [ 301, 302, 307, 308 ].include?(response.code.to_i) && response["Location"].present?
          redirected_uri = URI.join(uri.to_s, response["Location"])
          return perform_request(method: method, uri: redirected_uri, body: body, depth: depth, redirects: redirects + 1)
        end

        response
      end

      def build_uri(href)
        raw_href = href.to_s.strip
        return caldav_base_uri if raw_href.blank?

        return URI.parse(raw_href) if raw_href.start_with?("http://", "https://")

        URI.join(caldav_base_uri.to_s, normalize_href(raw_href))
      end

      def caldav_base_uri
        @caldav_base_uri ||= begin
          uri = URI.parse(ICLOUD_CALDAV_BASE_URL)
          if uri.host.blank?
            URI.parse(ICLOUD_CALDAV_BASE_URL)
          else
            uri.path = "/" if uri.path.blank?
            uri
          end
        rescue URI::InvalidURIError
          URI.parse(ICLOUD_CALDAV_BASE_URL)
        end
      end

      def normalize_href(raw_href)
        href = raw_href.to_s.strip
        return "" if href.blank?

        return URI.parse(href).request_uri if href.start_with?("http://", "https://")

        href.start_with?("/") ? href : "/#{href}"
      rescue URI::InvalidURIError
        href
      end

      def successful_prop(response_node)
        REXML::XPath.each(response_node, "d:propstat", XML_NS) do |propstat|
          status_text = text_at(propstat, "d:status").to_s
          next unless status_text.include?("200")

          prop_node = REXML::XPath.first(propstat, "d:prop", XML_NS)
          return prop_node if prop_node.present?
        end
        nil
      end

      def calendar_resource_type(prop_node)
        {
          calendar: REXML::XPath.first(prop_node, "d:resourcetype/c:calendar", XML_NS).present?,
          subscribed: REXML::XPath.first(prop_node, "d:resourcetype/cs:subscribed", XML_NS).present?
        }
      end

      def text_at(node, path)
        element = REXML::XPath.first(node, path, XML_NS)
        element&.text&.to_s&.strip
      end
    end
  end
end
