require "ipaddr"
require "uri"

module Notae
  module OutboundNetworkGuard
    PRIVATE_ENDPOINTS_ENV = "NOTAE_ALLOW_PRIVATE_NETWORK_ENDPOINTS"

    BLOCKED_HOSTS = %w[
      localhost
      localhost.localdomain
      ip6-localhost
      ip6-loopback
    ].freeze

    BLOCKED_SUFFIXES = %w[
      .localhost
      .local
      .internal
    ].freeze

    PRIVATE_IP_RANGES = [
      "0.0.0.0/8",
      "10.0.0.0/8",
      "100.64.0.0/10",
      "127.0.0.0/8",
      "169.254.0.0/16",
      "172.16.0.0/12",
      "192.0.0.0/24",
      "192.0.2.0/24",
      "192.168.0.0/16",
      "198.18.0.0/15",
      "198.51.100.0/24",
      "203.0.113.0/24",
      "224.0.0.0/4",
      "240.0.0.0/4",
      "::/128",
      "::1/128",
      "64:ff9b:1::/48",
      "100::/64",
      "2001:2::/48",
      "2001:db8::/32",
      "fc00::/7",
      "fe80::/10",
      "ff00::/8"
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    def public_http_url?(raw_url)
      uri = URI.parse(raw_url.to_s)
      uri.is_a?(URI::HTTP) && uri.host.present? && public_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def public_host?(raw_host)
      return true if private_endpoints_allowed?

      host = normalized_host(raw_host)
      return false if host.blank?
      return false if BLOCKED_HOSTS.include?(host)
      return false if BLOCKED_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

      ip = parse_ip(host)
      return true if ip.blank?

      PRIVATE_IP_RANGES.none? { |range| range.include?(ip) }
    end

    def private_endpoints_allowed?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(PRIVATE_ENDPOINTS_ENV, nil))
    end

    def normalized_host(raw_host)
      host = raw_host.to_s.strip.downcase.delete_suffix(".")
      return "" if host.blank?
      return Regexp.last_match(1) if host.match(/\A\[(.+)\]\z/)

      if host.count(":") == 1
        name, port = host.split(":", 2)
        return name if port.to_s.match?(/\A\d+\z/)
      end

      host
    end

    def parse_ip(host)
      IPAddr.new(host)
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end
