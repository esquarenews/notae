module CoverAssets
  class ApplyService
    COVER_SHIFT_STEP = 10

    def self.call(record:, workspace:, user:, payload:, unsplash_client: Unsplash::Client.new)
      new(record:, workspace:, user:, payload:, unsplash_client:).call
    end

    def initialize(record:, workspace:, user:, payload:, unsplash_client:)
      @record = record
      @workspace = workspace
      @user = user
      @payload = payload.to_h.symbolize_keys
      @unsplash_client = unsplash_client
    end

    def call
      apply_cover_action!
      apply_focal_shift!
      record
    rescue Unsplash::Client::Error => error
      record.errors.add(:base, error.message)
      record
    rescue Notae::UploadPolicy::InvalidUpload => error
      record.errors.add(:base, error.message)
      record
    end

    private

    attr_reader :record, :workspace, :user, :payload, :unsplash_client

    def apply_cover_action!
      case payload[:cover_action].to_s
      when "random"
        apply_random_cover!
      when "preset"
        apply_preset_cover!(payload[:cover_preset_key].to_s)
      when "upload"
        apply_uploaded_cover!(payload[:cover_image])
      when "recent"
        apply_recent_cover!(payload[:cover_asset_id].to_s)
      when "unsplash"
        apply_unsplash_cover!(payload[:cover_remote_id].to_s)
      when "clear"
        clear_cover!
      end
    end

    def apply_random_cover!
      record.cover_preset_key = record.class::COVER_PRESET_KEYS.sample
      record.cover_image.purge if record.cover_image.attached?
      clear_remote_cover_fields!
    end

    def apply_preset_cover!(key)
      return unless record.class::COVER_PRESET_KEYS.include?(key)

      record.cover_preset_key = key
      record.cover_image.purge if record.cover_image.attached?
      clear_remote_cover_fields!
    end

    def apply_uploaded_cover!(upload)
      return if upload.blank?

      Notae::UploadPolicy.validate_cover_image!(upload)
      record.cover_image.attach(upload)
      record.cover_preset_key = nil
      clear_remote_cover_fields!
      persist_uploaded_recent_cover!
    end

    def apply_recent_cover!(asset_id)
      asset = workspace.cover_assets.for_picker(workspace, user).with_attached_image.find_by(id: asset_id)
      return if asset.blank?

      record.cover_preset_key = nil

      if asset.remote?
        record.cover_image.purge if record.cover_image.attached?
        apply_remote_cover_from_asset!(asset)
      elsif asset.image.attached?
        record.cover_image.attach(asset.image.blob)
        clear_remote_cover_fields!
      end
    end

    def apply_unsplash_cover!(photo_id)
      return if photo_id.blank?

      photo = unsplash_client.photo(photo_id)
      unsplash_client.register_download!(photo[:download_location])

      record.cover_preset_key = nil
      record.cover_image.purge if record.cover_image.attached?
      assign_remote_cover_fields!(
        remote_url: photo[:full_url],
        remote_thumb_url: photo[:preview_url],
        artist_name: photo[:artist_name],
        artist_url: photo[:artist_url],
        source_name: photo[:source_name],
        source_url: photo[:source_url]
      )
      persist_unsplash_recent_cover!(photo)
    end

    def clear_cover!
      record.cover_preset_key = nil
      record.cover_image.purge if record.cover_image.attached?
      clear_remote_cover_fields!
    end

    def apply_focal_shift!
      shift_delta = { "up" => -COVER_SHIFT_STEP, "down" => COVER_SHIFT_STEP }[payload[:cover_shift].to_s]
      if shift_delta
        base = record.cover_focal_y || 50
        record.cover_focal_y = (base + shift_delta).clamp(0, 100)
      elsif payload[:cover_focal_y].present?
        record.cover_focal_y = payload[:cover_focal_y].to_i.clamp(0, 100)
      end
    end

    def clear_remote_cover_fields!
      assign_remote_cover_fields!(
        remote_url: nil,
        remote_thumb_url: nil,
        artist_name: nil,
        artist_url: nil,
        source_name: nil,
        source_url: nil
      )
    end

    def assign_remote_cover_fields!(remote_url:, remote_thumb_url:, artist_name:, artist_url:, source_name:, source_url:)
      record.cover_remote_url = remote_url
      record.cover_remote_thumb_url = remote_thumb_url
      record.cover_artist_name = artist_name
      record.cover_artist_url = artist_url
      record.cover_source_name = source_name
      record.cover_source_url = source_url
    end

    def apply_remote_cover_from_asset!(asset)
      assign_remote_cover_fields!(
        remote_url: asset.remote_image_url,
        remote_thumb_url: asset.remote_thumb_url,
        artist_name: asset.artist_name,
        artist_url: asset.artist_url,
        source_name: asset.source_name,
        source_url: asset.source_url
      )
    end

    def persist_uploaded_recent_cover!
      return unless record.cover_image.attached?

      asset = workspace.cover_assets.new(
        created_by: user,
        source_kind: "upload",
        label: uploaded_cover_label
      )
      asset.image.attach(record.cover_image.blob)
      asset.save!
    rescue ActiveRecord::RecordInvalid => error
      Rails.logger.warn("Recent cover upload save failed for #{record.class.name} #{record.id}: #{error.record.errors.full_messages.to_sentence}")
    rescue Notae::UploadPolicy::InvalidUpload => error
      Rails.logger.warn("Recent cover upload rejected for #{record.class.name} #{record.id}: #{error.message}")
    end

    def persist_unsplash_recent_cover!(photo)
      asset = workspace.cover_assets.find_or_initialize_by(
        created_by: user,
        source_kind: "unsplash",
        external_id: photo[:id]
      )
      asset.label = photo[:alt].presence || "Unsplash photo"
      asset.remote_image_url = photo[:full_url]
      asset.remote_thumb_url = photo[:preview_url]
      asset.artist_name = photo[:artist_name]
      asset.artist_url = photo[:artist_url]
      asset.source_name = photo[:source_name]
      asset.source_url = photo[:source_url]
      asset.save!
    rescue ActiveRecord::RecordInvalid => error
      Rails.logger.warn("Recent Unsplash cover save failed for #{record.class.name} #{record.id}: #{error.record.errors.full_messages.to_sentence}")
    end

    def uploaded_cover_label
      attached = payload[:cover_image]
      filename = attached.respond_to?(:original_filename) ? attached.original_filename.to_s : ""
      return "Uploaded cover" if filename.blank?

      File.basename(filename, File.extname(filename))
    end
  end
end
