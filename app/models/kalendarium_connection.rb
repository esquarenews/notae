class KalendariumConnection < ApplicationRecord
  PROVIDERS = %w[google icloud_caldav ics].freeze
  STATUSES = %w[connected sync_error disconnected].freeze

  encrypts :access_token
  encrypts :refresh_token
  encrypts :provider_username
  encrypts :provider_password
  encrypts :ics_url

  belongs_to :workspace
  belongs_to :owner, polymorphic: true
  belongs_to :created_by, class_name: "User"

  has_many :kalendarium_calendars, dependent: :destroy

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :label, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :owner_type, inclusion: { in: %w[User Workspace] }

  scope :active, -> { where(enabled: true) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  def shared_connection?
    owner_type == "Workspace"
  end

  def user_connection?
    owner_type == "User"
  end
end
