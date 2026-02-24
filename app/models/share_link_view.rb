class ShareLinkView < ApplicationRecord
  belongs_to :workspace
  belongs_to :page
  belongs_to :share_link

  validates :ip_address, presence: true
  validates :viewed_at, presence: true

  before_validation :set_workspace_and_page_from_share_link
  before_validation :set_default_viewed_at

  scope :recent_first, -> { order(viewed_at: :desc) }

  private

  def set_workspace_and_page_from_share_link
    return unless share_link.present?

    self.workspace ||= share_link.workspace
    self.page ||= share_link.page
  end

  def set_default_viewed_at
    self.viewed_at ||= Time.current
  end
end
