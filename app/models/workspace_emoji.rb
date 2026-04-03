class WorkspaceEmoji < ApplicationRecord
  belongs_to :workspace

  has_one_attached :image

  before_validation :normalize_name
  before_validation :assign_generated_name, if: -> { name.blank? }

  validates :name, presence: true, uniqueness: { scope: :workspace_id, case_sensitive: false }
  validate :image_must_be_attached
  validate :image_must_be_supported

  scope :ordered, -> { order(:created_at, :id) }

  def icon_token
    Page.custom_emoji_token(id)
  end

  def display_name
    name.to_s.tr("_-", " ").squeeze(" ").strip.presence&.titleize || "Custom emoji"
  end

  private

  def normalize_name
    self.name = name.to_s.strip.squeeze(" ").presence
  end

  def assign_generated_name
    base_name = image&.attachment&.blob&.filename&.base.to_s.parameterize(separator: "_").presence || "custom_emoji"
    candidate = base_name
    suffix = 2

    while workspace&.custom_emojis&.where.not(id: id).exists?(name: candidate)
      candidate = "#{base_name}_#{suffix}"
      suffix += 1
    end

    self.name = candidate
  end

  def image_must_be_attached
    errors.add(:image, "must be uploaded") unless image.attached?
  end

  def image_must_be_supported
    return unless image.attached?

    allowed_types = %w[image/png image/jpeg image/gif image/webp image/svg+xml]
    return if allowed_types.include?(image.blob.content_type)

    errors.add(:image, "must be a PNG, JPEG, GIF, WebP, or SVG")
  end
end
