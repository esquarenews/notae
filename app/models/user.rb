class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :created_pages, class_name: "Page", foreign_key: :created_by_id, inverse_of: :created_by
  has_many :created_blocks, class_name: "Block", foreign_key: :created_by_id, inverse_of: :created_by
  has_many :page_shares, dependent: :destroy
  has_many :shared_pages, through: :page_shares, source: :page
  has_many :audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :destroy
  has_many :authored_comments, class_name: "Comment", foreign_key: :author_id, inverse_of: :author
  has_many :resolved_comments, class_name: "Comment", foreign_key: :resolved_by_id, inverse_of: :resolved_by
  has_many :notifications, foreign_key: :recipient_id, inverse_of: :recipient, dependent: :destroy
  has_many :triggered_notifications, class_name: "Notification", foreign_key: :actor_id, inverse_of: :actor
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, inverse_of: :invited_by
  has_many :accepted_invitations, class_name: "Invitation", foreign_key: :accepted_by_id, inverse_of: :accepted_by
  has_many :created_share_links, class_name: "ShareLink", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :created_database_views, class_name: "DatabaseView", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :requested_page_exports, class_name: "PageExport", foreign_key: :requested_by_id, inverse_of: :requested_by, dependent: :destroy
  has_many :created_page_templates, class_name: "PageTemplate", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
