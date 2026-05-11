# frozen_string_literal: true

module Notae
  module UploadPolicy
    InvalidUpload = Class.new(StandardError)

    SAFE_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
    SAFE_VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze
    SAFE_AUDIO_TYPES = %w[audio/mpeg audio/mp4 audio/wav audio/webm audio/ogg].freeze
    SAFE_DOCUMENT_TYPES = %w[
      text/plain
      text/markdown
      text/csv
      application/pdf
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze
    SAFE_MEDIA_TYPES = (SAFE_IMAGE_TYPES + SAFE_VIDEO_TYPES + SAFE_AUDIO_TYPES).freeze
    SAFE_FILE_TYPES = (SAFE_MEDIA_TYPES + SAFE_DOCUMENT_TYPES).freeze

    MAX_IMAGE_BYTES = 10.megabytes
    MAX_FILE_BYTES = 250.megabytes

    module_function

    def validate!(upload, allowed_types:, max_bytes:, label: "File")
      raise InvalidUpload, "#{label} is missing." if upload.blank?

      size = byte_size(upload)
      if size.to_i > max_bytes
        raise InvalidUpload, "#{label} must be #{ActiveSupport::NumberHelper.number_to_human_size(max_bytes)} or smaller."
      end

      detected_type = content_type(upload)
      return true if allowed_types.include?(detected_type)

      raise InvalidUpload, "#{label} type is not supported."
    end

    def validate_block_upload!(upload, block_type:)
      case block_type.to_s
      when "image"
        validate!(upload, allowed_types: SAFE_IMAGE_TYPES, max_bytes: MAX_IMAGE_BYTES, label: "Image")
      when "video"
        validate!(upload, allowed_types: SAFE_VIDEO_TYPES, max_bytes: MAX_FILE_BYTES, label: "Video")
      else
        validate!(upload, allowed_types: SAFE_FILE_TYPES, max_bytes: MAX_FILE_BYTES, label: "File")
      end
    end

    def validate_cover_image!(upload)
      validate!(upload, allowed_types: SAFE_IMAGE_TYPES, max_bytes: MAX_IMAGE_BYTES, label: "Cover image")
    end

    def validate_emoji_image!(upload)
      validate!(upload, allowed_types: SAFE_IMAGE_TYPES, max_bytes: MAX_IMAGE_BYTES, label: "Emoji image")
    end

    def validate_page_media_import!(upload)
      validate!(upload, allowed_types: SAFE_MEDIA_TYPES, max_bytes: MAX_FILE_BYTES, label: "Imported media")
    end

    def safe_inline_image_content_type?(content_type)
      SAFE_IMAGE_TYPES.include?(content_type.to_s)
    end

    def safe_inline_media_content_type?(content_type)
      SAFE_MEDIA_TYPES.include?(content_type.to_s)
    end

    def content_type(upload)
      declared_type = upload.respond_to?(:content_type) ? upload.content_type.to_s : nil
      filename = upload.respond_to?(:original_filename) ? upload.original_filename.to_s : nil
      io = upload.respond_to?(:tempfile) ? upload.tempfile : nil

      if io.present?
        io.rewind if io.respond_to?(:rewind)
        detected_type = Marcel::MimeType.for(io, name: filename, declared_type: declared_type)
        io.rewind if io.respond_to?(:rewind)
        return detected_type.to_s
      end

      declared_type.to_s
    end

    def byte_size(upload)
      return upload.size if upload.respond_to?(:size)
      return File.size(upload.tempfile.path) if upload.respond_to?(:tempfile) && upload.tempfile.respond_to?(:path)

      0
    end
  end
end
