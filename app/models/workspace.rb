class Workspace < ApplicationRecord
  include PgSearch::Model

  has_paper_trail

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :databases, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :page_links, dependent: :destroy
  has_many :audit_events, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  before_validation :normalize_slug

  pg_search_scope :search_by_name,
                  against: :name,
                  using: { tsearch: { prefix: true } }

  private

  def normalize_slug
    return if slug.blank?

    self.slug = slug.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
  end
end
