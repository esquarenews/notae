module IconTokenSupport
  extend ActiveSupport::Concern

  CUSTOM_EMOJI_PREFIX = "custom-emoji:".freeze

  class_methods do
    def custom_emoji_token(id)
      "#{CUSTOM_EMOJI_PREFIX}#{id}"
    end

    def custom_emoji_token?(value)
      value.to_s.start_with?(CUSTOM_EMOJI_PREFIX)
    end

    def custom_emoji_id_from_token(value)
      token = value.to_s
      return if token.blank?
      return unless custom_emoji_token?(token)

      token.delete_prefix(CUSTOM_EMOJI_PREFIX)
    end
  end

  private

  def normalize_icon_token(value)
    normalized = value.to_s.strip.presence
    return if normalized.blank?
    return normalized if self.class.custom_emoji_token?(normalized)

    normalized.scan(/\X/).first(2).join.presence
  end
end
