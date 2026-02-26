class Workspace < ApplicationRecord
  include PgSearch::Model

  DISCO_ICON_OPTIONS = [
    "🪩",
    "🎵",
    "🎶",
    "🕺",
    "💃",
    "🎧",
    "🎤",
    "✨",
    "🌈",
    "💜",
    "🌟",
    "🛸"
  ].freeze

  has_paper_trail

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :databases, dependent: :destroy
  has_many :database_views, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :page_links, dependent: :destroy
  has_many :audit_events, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :share_link_views, dependent: :destroy
  has_many :page_exports, dependent: :destroy
  has_many :page_templates, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :search_chunks, dependent: :destroy

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true
  validates :name, length: { maximum: 65 }
  validates :slug, presence: true, uniqueness: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :icon, inclusion: { in: DISCO_ICON_OPTIONS }, allow_blank: true
  validates :join_link_enabled, inclusion: { in: [ true, false ] }
  validates :join_link_token, uniqueness: true, allow_blank: true

  before_validation :normalize_slug

  pg_search_scope :search_by_name,
                  against: :name,
                  using: { tsearch: { prefix: true } }

  def display_icon
    icon.presence || "🏠"
  end

  def archived?
    archived_at.present?
  end

  def ensure_join_link_token!
    return if join_link_token.present?

    update!(join_link_token: self.class.generate_join_link_token)
  end

  def rotate_join_link_token!
    update!(join_link_token: self.class.generate_join_link_token)
  end

  def self.generate_join_link_token
    loop do
      candidate = SecureRandom.urlsafe_base64(32)
      return candidate unless exists?(join_link_token: candidate)
    end
  end

  private

  def normalize_slug
    return if slug.blank?

    self.slug = slug.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
  end
end
