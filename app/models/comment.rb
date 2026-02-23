class Comment < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"
  belongs_to :resolved_by, class_name: "User", optional: true

  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :body, presence: true

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  before_validation :set_workspace_from_commentable

  def resolved?
    resolved_at.present?
  end

  def resolve!(by:)
    update!(resolved_at: Time.current, resolved_by: by)
  end

  def unresolve!
    update!(resolved_at: nil, resolved_by: nil)
  end

  private

  def set_workspace_from_commentable
    self.workspace = commentable.workspace if commentable.respond_to?(:workspace)
  end
end
