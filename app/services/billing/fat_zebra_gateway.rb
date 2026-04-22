module Billing
  class FatZebraGateway
    PROVIDER_KEY = WorkspaceSubscription::PROVIDER_FAT_ZEBRA

    def self.configured?
      ENV["FAT_ZEBRA_USERNAME"].present? && ENV["FAT_ZEBRA_TOKEN"].present?
    end

    def self.display_name
      "Fat Zebra"
    end

    def self.hosted_payments_available?
      configured?
    end

    def self.webhook_secret
      ENV["FAT_ZEBRA_WEBHOOK_SECRET"].to_s
    end

    def self.webhook_authentication_required?
      webhook_secret.present? || Rails.env.production?
    end
  end
end
