class PageLink < ApplicationRecord
  belongs_to :workspace
  belongs_to :source_page, class_name: "Page"
  belongs_to :target_page, class_name: "Page"
  belongs_to :source_block, class_name: "Block", optional: true

  validates :target_page_id, uniqueness: { scope: :source_block_id, if: -> { source_block_id.present? } }
  validate :same_workspace

  scope :for_target, ->(page) { where(target_page_id: page.id) }

  private

  def same_workspace
    return if workspace.blank? || source_page.blank? || target_page.blank?
    return if source_page.workspace_id == workspace_id && target_page.workspace_id == workspace_id

    errors.add(:workspace_id, "must match linked pages")
  end
end
