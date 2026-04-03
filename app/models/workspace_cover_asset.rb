class WorkspaceCoverAsset < ApplicationRecord
  SOURCE_KINDS = %w[upload unsplash].freeze
  DEFAULT_SOURCE_NAME = "Unsplash".freeze

  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  has_one_attached :image

  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :label, presence: true
  validates :image, presence: true, if: :upload?
  validates :remote_image_url, presence: true, if: :unsplash?
  validates :artist_name, presence: true, if: :unsplash?
  validates :artist_url, presence: true, if: :unsplash?
  validates :source_url, presence: true, if: :unsplash?

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_picker, ->(workspace, user) { where(workspace: workspace, created_by: user).recent_first }

  def upload?
    source_kind == "upload"
  end

  def unsplash?
    source_kind == "unsplash"
  end

  def remote?
    remote_image_url.present?
  end

  def preview_url
    remote_thumb_url.presence || remote_image_url.presence
  end

  def display_source_name
    source_name.presence || DEFAULT_SOURCE_NAME
  end
end
