require "uri"
require "ipaddr"
require "resolv"

class WebPushSubscription < ApplicationRecord
  belongs_to :user
  has_many :delivery_attempts, class_name: "WebPushDeliveryAttempt", foreign_key: :subscription_id, dependent: :nullify

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, presence: true
  validates :auth, presence: true
  validate :endpoint_must_be_public_https

  def endpoint_host
    URI.parse(endpoint).host.presence || endpoint
  rescue URI::InvalidURIError
    endpoint
  end

  def delivery_status
    if last_error_at.present? && (last_delivered_at.blank? || last_error_at > last_delivered_at)
      :failing
    elsif last_delivered_at.present?
      :healthy
    else
      :pending
    end
  end

  def valid_public_endpoint?
    uri = URI.parse(endpoint)
    return false unless uri.is_a?(URI::HTTPS)
    return false if uri.host.blank?
    return false if uri.userinfo.present?
    return false if uri.host.casecmp("localhost").zero?

    host_ips = resolved_host_ips(uri.host)
    return false if host_ips.empty?

    host_ips.none? { |ip| private_or_internal_ip?(ip) }
  rescue URI::InvalidURIError
    false
  end

  private

  def endpoint_must_be_public_https
    return if endpoint.blank?
    return if valid_public_endpoint?

    errors.add(:endpoint, "must be a valid public HTTPS URL")
  end

  def resolved_host_ips(host)
    Addrinfo.getaddrinfo(host, nil).map { |addr| addr.ip_address }.uniq
  rescue SocketError
    []
  end

  def private_or_internal_ip?(ip)
    ipaddr = IPAddr.new(ip)
    return true if ipaddr.loopback? || ipaddr.link_local? || ipaddr.private?

    ipaddr == IPAddr.new("0.0.0.0") || ipaddr == IPAddr.new("::") || ipaddr.multicast?
  rescue IPAddr::InvalidAddressError
    true
  end
end
