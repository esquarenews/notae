class Page < ApplicationRecord
  include PgSearch::Model

  has_paper_trail

  attribute :permission_mode, :integer, default: 0
  enum :permission_mode, { shared_to_workspace: 0, private_page: 1, specific_users: 2 }, default: :shared_to_workspace

  belongs_to :workspace
  belongs_to :parent_page, class_name: "Page", optional: true
  belongs_to :created_by, class_name: "User"

  has_many :child_pages, -> { order(:created_at) }, class_name: "Page", foreign_key: :parent_page_id, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :page_shares, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :shared_users, through: :page_shares, source: :user
  has_many :outgoing_page_links, class_name: "PageLink", foreign_key: :source_page_id, dependent: :destroy
  has_many :incoming_page_links, class_name: "PageLink", foreign_key: :target_page_id, dependent: :destroy

  validates :title, presence: true
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

  private

  def set_workspace_from_parent
    self.workspace = parent_page.workspace
  end

  def parent_page_workspace_matches
    return if parent_page.blank?
    return if parent_page.workspace_id == workspace_id

    errors.add(:parent_page_id, "must belong to the same workspace")
  end
end
