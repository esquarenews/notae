class Page < ApplicationRecord
  include PgSearch::Model

  has_paper_trail
  COVER_PRESET_KEYS = %w[
    aurora-dunes
    basalt-ink
    citrus-wave
    dawn-grid
  ].freeze
  FONT_STYLES = %w[default serif mono].freeze
  ICON_SUGGESTIONS = %w[📄 ✨ 🧠 📝 📌 🧭 🚀 🗂️ 🌿 🌅].freeze

  attribute :permission_mode, :integer, default: 0
  enum :permission_mode, { shared_to_workspace: 0, private_page: 1, specific_users: 2 }, default: :shared_to_workspace

  belongs_to :workspace
  belongs_to :parent_page, class_name: "Page", optional: true
  belongs_to :created_by, class_name: "User"

  has_many :child_pages, -> { order(:created_at) }, class_name: "Page", foreign_key: :parent_page_id, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :page_shares, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :page_exports, dependent: :destroy
  has_many :page_templates, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :shared_users, through: :page_shares, source: :user
  has_many :outgoing_page_links, class_name: "PageLink", foreign_key: :source_page_id, dependent: :destroy
  has_many :incoming_page_links, class_name: "PageLink", foreign_key: :target_page_id, dependent: :destroy
  has_one_attached :cover_image

  validates :title, presence: true
  validates :font_style, inclusion: { in: FONT_STYLES }
  validates :cover_preset_key, inclusion: { in: COVER_PRESET_KEYS }, allow_blank: true
  validates :cover_focal_y,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :small_text, inclusion: { in: [ true, false ] }
  validates :full_width, inclusion: { in: [ true, false ] }
  validates :locked, inclusion: { in: [ true, false ] }
  validates :suggest_edits, inclusion: { in: [ true, false ] }
  validate :parent_page_workspace_matches

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  pg_search_scope :search_full_text,
                  against: :title,
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_parent, if: -> { workspace_id.nil? && parent_page.present? }
  before_validation :normalize_icon

  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end

  def visible_to_specific_user?(user)
    return false unless user
    return true if created_by_id == user.id

    page_shares.exists?(user_id: user.id)
  end

  def cover?
    cover_image.attached? || cover_preset_key.present?
  end

  private

  def set_workspace_from_parent
    self.workspace = parent_page.workspace
  end

  def normalize_icon
    normalized = icon.to_s.strip.presence
    self.icon = normalized&.scan(/\X/)&.first(2)&.join
  end

  def parent_page_workspace_matches
    return if parent_page.blank?
    return if parent_page.workspace_id == workspace_id

    errors.add(:parent_page_id, "must belong to the same workspace")
  end
end
