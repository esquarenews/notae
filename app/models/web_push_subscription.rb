require "uri"

class WebPushSubscription < ApplicationRecord
  belongs_to :user
  has_many :delivery_attempts, class_name: "WebPushDeliveryAttempt", foreign_key: :subscription_id, dependent: :nullify

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, presence: true
  validates :auth, presence: true

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
end
