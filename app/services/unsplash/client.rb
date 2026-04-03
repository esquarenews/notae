require "cgi"
require "json"
require "net/http"
require "uri"

module Unsplash
  class Client
    APP_NAME = "notae".freeze
    API_BASE_URL = "https://api.unsplash.com".freeze
    WEBSITE_BASE_URL = "https://unsplash.com".freeze
    DEFAULT_PER_PAGE = 12

    class Error < StandardError; end
    class ConfigurationError < Error; end
    class RequestError < Error; end

    def initialize(access_key: nil)
      @access_key = access_key.presence || ENV["UNSPLASH_ACCESS_KEY"].presence || Rails.application.credentials.dig(:unsplash, :access_key).presence
    end

    def configured?
      @access_key.present?
    end

    def list_photos(page:, per_page: DEFAULT_PER_PAGE)
      uri = build_api_uri("/photos", page:, per_page:, order_by: "popular")
      response = perform_json_request(uri)

      {
        photos: Array(response.fetch(:body)).filter_map { |item| normalize_photo(item) },
        page: page.to_i,
        per_page: per_page.to_i,
        total_pages: extract_total_pages(headers: response.fetch(:headers), body: response.fetch(:body), page:, per_page:)
      }
    end

    def search_photos(query:, page:, per_page: DEFAULT_PER_PAGE)
      uri = build_api_uri("/search/photos", query:, page:, per_page:)
      body = perform_json_request(uri).fetch(:body)

      {
        photos: Array(body["results"]).filter_map { |item| normalize_photo(item) },
        page: body["page"].presence&.to_i || page.to_i,
        per_page: body["per_page"].to_i,
        total_pages: extract_total_pages(headers: {}, body:, page:, per_page:)
      }
    end

    def photo(photo_id)
      uri = build_api_uri("/photos/#{CGI.escape(photo_id.to_s)}")
      body = perform_json_request(uri).fetch(:body)
      normalize_photo(body)
    end

    def register_download!(download_location)
      return if download_location.blank?

      uri = URI.parse(download_location)
      perform_json_request(uri)
    end

    private

    def build_api_uri(path, **params)
      uri = URI.join(API_BASE_URL, path)
      uri.query = URI.encode_www_form(params.compact_blank)
      uri
    end

    def perform_json_request(uri)
      raise ConfigurationError, "Unsplash is not configured. Set UNSPLASH_ACCESS_KEY or credentials[:unsplash][:access_key]." unless configured?

      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Client-ID #{@access_key}"
        request["Accept-Version"] = "v1"
        request["Accept"] = "application/json"
        response = http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "Unsplash request failed with #{response.code}."
      end

      {
        body: response.body.present? ? JSON.parse(response.body) : {},
        headers: response.to_hash.transform_values { |values| Array(values).last }
      }
    rescue JSON::ParserError => error
      raise RequestError, "Unsplash returned invalid JSON: #{error.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => error
      raise RequestError, "Unsplash request failed: #{error.message}"
    end

    def normalize_photo(payload)
      return nil if payload.blank?

      photographer_profile = referral_url(payload.dig("user", "links", "html"))
      source_url = referral_url(WEBSITE_BASE_URL)

      {
        id: payload["id"].to_s,
        alt: payload["alt_description"].presence || payload["description"].presence || "Unsplash photo",
        color: payload["color"].presence,
        preview_url: payload.dig("urls", "small").presence || payload.dig("urls", "thumb").presence,
        full_url: payload.dig("urls", "regular").presence || payload.dig("urls", "full").presence,
        artist_name: payload.dig("user", "name").to_s,
        artist_url: photographer_profile,
        source_name: WorkspaceCoverAsset::DEFAULT_SOURCE_NAME,
        source_url: source_url,
        download_location: payload.dig("links", "download_location").to_s
      }
    end

    def referral_url(url)
      return nil if url.blank?

      uri = URI.parse(url)
      query_values = URI.decode_www_form(String(uri.query)).to_h
      query_values["utm_source"] = APP_NAME
      query_values["utm_medium"] = "referral"
      uri.query = URI.encode_www_form(query_values)
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def extract_total_pages(headers:, body:, page:, per_page:)
      return body["total_pages"].to_i if body.is_a?(Hash) && body["total_pages"].present?

      total_pages = headers["x-total-pages"].to_i
      return total_pages if total_pages.positive?

      total = headers["x-total"].to_i
      response_per_page = headers["x-per-page"].to_i
      divisor = response_per_page.positive? ? response_per_page : per_page.to_i
      if total.positive? && divisor.positive?
        return (total.to_f / divisor).ceil
      end

      extract_last_page_from_link(headers["link"]) || page.to_i
    end

    def extract_last_page_from_link(link_header)
      return nil if link_header.blank?

      last_link = link_header.to_s.split(",").find { |entry| entry.include?('rel="last"') }
      return nil if last_link.blank?

      matched_url = last_link[/<([^>]+)>/, 1]
      return nil if matched_url.blank?

      uri = URI.parse(matched_url)
      params = URI.decode_www_form(String(uri.query)).to_h
      page = params["page"].to_i
      page.positive? ? page : nil
    rescue URI::InvalidURIError
      nil
    end
  end
end
