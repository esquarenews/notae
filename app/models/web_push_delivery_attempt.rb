class WebPushDeliveryAttempt < ApplicationRecord
  belongs_to :user
  belongs_to :workspace, optional: true
  belongs_to :subscription, class_name: "WebPushSubscription", optional: true
  belongs_to :notification, optional: true

  enum :status, { delivered: 0, failed: 1, stale_subscription: 2 }, default: :delivered, scopes: false

  validates :endpoint_host, presence: true
  validates :status, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def status_pill_class
    return "is-ok" if delivered?
    return "is-warn" if stale_subscription?

    "is-error"
  end

  def status_label
    return "Subscription expired" if stale_subscription?

    status.humanize
  end

  def display_title
    title.to_s.presence || notification_type.to_s.humanize.presence || "Push delivery"
  end

  def display_body
    body.to_s.presence || error_message.to_s.presence
  end
end
