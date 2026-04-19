module Users
  class AvatarUploadProcessor
    MAX_DIMENSION = 512
    SUPPORTED_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze

    class Error < StandardError; end
    class UnsupportedTypeError < Error; end
    class ProcessingError < Error; end

    def initialize(upload:)
      @upload = upload
    end

    def call
      raise UnsupportedTypeError, "Avatar must be a PNG, JPEG, WebP, or GIF image." unless supported_content_type?

      processed_tempfile = ImageProcessing::MiniMagick
        .source(source_path)
        .strip
        .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
        .call

      {
        io: File.open(processed_tempfile.path, "rb"),
        filename: processed_filename,
        content_type: upload.content_type,
        tempfile: processed_tempfile
      }
    rescue UnsupportedTypeError
      raise
    rescue StandardError => error
      Rails.logger.warn("Avatar processing failed: #{error.class}: #{error.message}")
      raise ProcessingError, "Avatar image could not be processed."
    end

    def self.close(attachment_payload)
      return if attachment_payload.blank?

      attachment_payload[:io]&.close
      attachment_payload[:tempfile]&.close!
    end

    private

    attr_reader :upload

    def supported_content_type?
      SUPPORTED_CONTENT_TYPES.include?(upload.content_type.to_s)
    end

    def source_path
      return upload.tempfile.path if upload.respond_to?(:tempfile) && upload.tempfile.present?
      return upload.path if upload.respond_to?(:path)

      raise ProcessingError, "Avatar upload is missing a source file."
    end

    def processed_filename
      base = upload.original_filename.to_s.strip.presence || "avatar"
      extension = File.extname(base)
      stem = extension.present? ? File.basename(base, extension) : base
      "#{stem.parameterize.presence || "avatar"}#{extension.presence || default_extension}"
    end

    def default_extension
      case upload.content_type.to_s
      when "image/png" then ".png"
      when "image/jpeg" then ".jpg"
      when "image/webp" then ".webp"
      when "image/gif" then ".gif"
      else ""
      end
    end
  end
end
