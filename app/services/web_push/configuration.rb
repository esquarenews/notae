module WebPush
  class Configuration
    class << self
      def configured?
        public_key.present? && private_key.present?
      end

      def public_key
        ENV["VAPID_PUBLIC_KEY"].to_s.strip.presence
      end

      def private_key
        ENV["VAPID_PRIVATE_KEY"].to_s.strip.presence
      end

      def subject
        ENV["VAPID_SUBJECT"].to_s.strip.presence || "mailto:support@notae.local"
      end

      def vapid_options
        return {} unless configured?

        {
          subject: subject,
          public_key: public_key,
          private_key: private_key
        }
      end
    end
  end
end
