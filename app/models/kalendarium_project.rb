class KalendariumProject < ApplicationRecord
  belongs_to :workspace
  belongs_to :kalendarium_calendar, optional: true
  belongs_to :linked_page, class_name: "Page", optional: true
  belongs_to :created_by, class_name: "User"

  has_many :kalendarium_events, dependent: :nullify

  validates :name, presence: true, length: { maximum: 160 }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :color_hex, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :default_slug
  before_validation :normalize_slug

  def archived?
    archived_at.present?
  end

  private

  def default_slug
    self.slug = name if slug.blank? && name.present?
  end

  def normalize_slug
    return if slug.blank?

    self.slug = slug.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\-+\z/, "")
  end
end
