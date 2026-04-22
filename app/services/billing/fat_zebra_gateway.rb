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
  end
end
