module Notifications
  class InternalPathSanitizer
    def self.call(path, fallback:)
      new(path: path, fallback: fallback).call
    end

    def initialize(path:, fallback:)
      @path = path.to_s.strip
      @fallback = fallback
    end

    def call
      return fallback if path.blank?
      return fallback unless relative_app_path?
      return path if routable_path?

      fallback
    end

    private

    attr_reader :path, :fallback

    def relative_app_path?
      uri = URI.parse(path)
      uri.scheme.blank? && uri.host.blank? && uri.path.start_with?("/") && !path.start_with?("//")
    rescue URI::InvalidURIError
      false
    end

    def routable_path?
      uri = URI.parse(path)
      Rails.application.routes.recognize_path(uri.path, method: :get)
      true
    rescue ActionController::RoutingError, URI::InvalidURIError
      false
    end
  end
end
