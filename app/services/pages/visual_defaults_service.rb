module Pages
  class VisualDefaultsService
    def self.apply(record:, source:)
      new(record:, source:).apply
    end

    def initialize(record:, source:)
      @record = record
      @source = source
    end

    def apply
      return record if source.blank?

      inherit_icon!
      inherit_cover!
      record
    end

    private

    attr_reader :record, :source

    def inherit_icon!
      return unless record.respond_to?(:icon) && record.respond_to?(:icon=)
      return if record.icon.present? || source.icon.blank?

      record.icon = source.icon
    end

    def inherit_cover!
      return unless record_supports_cover_defaults?
      return unless source_supports_cover_defaults?
      return if record.cover?
      return unless source.cover?

      record.cover_preset_key = source.cover_preset_key if record.respond_to?(:cover_preset_key=)
      record.cover_focal_y = source.cover_focal_y if record.respond_to?(:cover_focal_y=)

      if record.respond_to?(:cover_remote_url=)
        record.cover_remote_url = source.cover_remote_url
        record.cover_remote_thumb_url = source.cover_remote_thumb_url if record.respond_to?(:cover_remote_thumb_url=)
        record.cover_artist_name = source.cover_artist_name if record.respond_to?(:cover_artist_name=)
        record.cover_artist_url = source.cover_artist_url if record.respond_to?(:cover_artist_url=)
        record.cover_source_name = source.cover_source_name if record.respond_to?(:cover_source_name=)
        record.cover_source_url = source.cover_source_url if record.respond_to?(:cover_source_url=)
      end

      inherit_cover_image!
    end

    def inherit_cover_image!
      return unless record.respond_to?(:cover_image) && source.respond_to?(:cover_image)
      return unless source.cover_image.attached?
      return if record.cover_image.attached?
      return if record.cover_preset_key.present?
      return if record.respond_to?(:cover_remote_url) && record.cover_remote_url.present?

      record.cover_image.attach(source.cover_image.blob)
    end

    def record_supports_cover_defaults?
      record.respond_to?(:cover?) && record.respond_to?(:cover_image)
    end

    def source_supports_cover_defaults?
      source.respond_to?(:cover?) && source.respond_to?(:cover_image)
    end
  end
end
