class Workspace < ApplicationRecord
  encrypts :join_link_token, deterministic: true

  include PgSearch::Model

  WORKSPACE_COLOR_OPTIONS = [
    { label: "Rose", value: "#f43f5e" },
    { label: "Pink", value: "#ec4899" },
    { label: "Fuchsia", value: "#d946ef" },
    { label: "Purple", value: "#a855f7" },
    { label: "Violet", value: "#8b5cf6" },
    { label: "Indigo", value: "#6366f1" },
    { label: "Blue", value: "#3b82f6" },
    { label: "Sky", value: "#0ea5e9" },
    { label: "Cyan", value: "#06b6d4" },
    { label: "Teal", value: "#14b8a6" },
    { label: "Emerald", value: "#10b981" },
    { label: "Green", value: "#22c55e" },
    { label: "Lime", value: "#84cc16" },
    { label: "Spring", value: "#a3e635" },
    { label: "Yellow", value: "#eab308" },
    { label: "Amber", value: "#f59e0b" },
    { label: "Orange", value: "#f97316" },
    { label: "Red", value: "#ef4444" },
    { label: "Coral", value: "#fb7185" },
    { label: "Blush", value: "#f472b6" },
    { label: "Orchid", value: "#e879f9" },
    { label: "Plum", value: "#9333ea" },
    { label: "Iris", value: "#7c3aed" },
    { label: "Cobalt", value: "#2563eb" },
    { label: "Cerulean", value: "#0284c7" },
    { label: "Lagoon", value: "#0891b2" },
    { label: "Aqua", value: "#0f766e" },
    { label: "Mint", value: "#0d9488" },
    { label: "Forest", value: "#16a34a" },
    { label: "Olive", value: "#65a30d" },
    { label: "Gold", value: "#ca8a04" },
    { label: "Copper", value: "#c2410c" },
    { label: "Terracotta", value: "#ea580c" },
    { label: "Berry", value: "#be123c" },
    { label: "Slate", value: "#475569" },
    { label: "Stone", value: "#78716c" }
  ].freeze
  WORKSPACE_COLOR_VALUES = WORKSPACE_COLOR_OPTIONS.map { |option| option.fetch(:value) }.freeze
  DEFAULT_COLOR = WORKSPACE_COLOR_OPTIONS.first.fetch(:value)
  SHELL_STATUS_BAR_MODE_ALL = "all".freeze
  SHELL_STATUS_BAR_MODE_OFF = "off".freeze
  SHELL_STATUS_BAR_MODE_TIME_ONLY = "time_only".freeze
  SHELL_STATUS_BAR_MODE_ALERTS_ONLY = "alerts_only".freeze
  SHELL_STATUS_BAR_MODE_OPTIONS = [
    { label: "Date/time + alerts", value: SHELL_STATUS_BAR_MODE_ALL },
    { label: "Date/time only", value: SHELL_STATUS_BAR_MODE_TIME_ONLY },
    { label: "Alerts only", value: SHELL_STATUS_BAR_MODE_ALERTS_ONLY },
    { label: "Off", value: SHELL_STATUS_BAR_MODE_OFF }
  ].freeze
  SHELL_STATUS_BAR_MODES = SHELL_STATUS_BAR_MODE_OPTIONS.map { |option| option.fetch(:value) }.freeze
  SHELL_STATUS_BAR_MODES_WITH_CLOCK = [ SHELL_STATUS_BAR_MODE_ALL, SHELL_STATUS_BAR_MODE_TIME_ONLY ].freeze
  SHELL_STATUS_BAR_MODES_WITH_ALERTS = [ SHELL_STATUS_BAR_MODE_ALL, SHELL_STATUS_BAR_MODE_ALERTS_ONLY ].freeze
  DEFAULT_SHELL_STATUS_BAR_MODE = SHELL_STATUS_BAR_MODE_ALL

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
  has_many :database_shares, through: :databases
  has_many :page_links, dependent: :destroy
  has_many :audit_events, dependent: :destroy
  has_many :api_token_audit_events, dependent: :nullify
  has_many :share_links, dependent: :destroy
  has_many :share_link_views, dependent: :destroy
  has_many :database_share_links, dependent: :destroy
  has_many :page_exports, dependent: :destroy
  has_many :page_templates, dependent: :destroy
  has_many :database_templates, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :custom_emojis, class_name: "WorkspaceEmoji", dependent: :destroy
  has_many :cover_assets, class_name: "WorkspaceCoverAsset", dependent: :destroy
  has_many :search_chunks, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_many :ai_conversations, dependent: :destroy
  has_many :knowledge_suggestions, dependent: :destroy
  has_many :epistularium_accounts, dependent: :destroy
  has_many :epistularium_messages, dependent: :destroy
  has_many :kalendarium_connections, dependent: :destroy
  has_many :kalendarium_calendars, dependent: :destroy
  has_many :kalendarium_projects, dependent: :destroy
  has_many :kalendarium_events, dependent: :destroy
  has_many :kalendarium_write_proposals, dependent: :destroy
  has_many :meeting_sessions, dependent: :destroy
  has_many :meeting_speaker_aliases, dependent: :destroy
  has_many :workflow_runs, dependent: :destroy
  has_one :agent_policy, dependent: :destroy

  scope :active, lambda {
    if column_names.include?("archived_at")
      where(archived_at: nil)
    else
      all
    end
  }

  validates :name, presence: true
  validates :name, length: { maximum: 65 }
  validates :slug, presence: true, uniqueness: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :workspace_color, presence: true, inclusion: { in: WORKSPACE_COLOR_VALUES }
  validates :shell_status_bar_mode, presence: true, inclusion: { in: SHELL_STATUS_BAR_MODES }
  validates :join_link_enabled, inclusion: { in: [ true, false ] }
  validates :join_link_token, uniqueness: true, allow_blank: true

  before_validation :default_slug_from_name
  before_validation :normalize_slug
  before_validation :normalize_workspace_color
  before_validation :normalize_shell_status_bar_mode

  pg_search_scope :search_by_name,
                  against: :name,
                  using: { tsearch: { prefix: true } }

  def display_color
    workspace_color.presence || DEFAULT_COLOR
  end

  def display_shell_status_bar_mode
    shell_status_bar_mode.presence || DEFAULT_SHELL_STATUS_BAR_MODE
  end

  def archived?
    return false unless has_attribute?(:archived_at)

    self[:archived_at].present?
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

  def default_slug_from_name
    self.slug = name if slug.blank? && name.present?
  end

  def normalize_slug
    return if slug.blank?

    self.slug = slug.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
  end

  def normalize_workspace_color
    return if workspace_color.blank?

    self.workspace_color = workspace_color.to_s.strip.downcase
  end

  def normalize_shell_status_bar_mode
    self.shell_status_bar_mode = shell_status_bar_mode.to_s.strip.downcase.presence || DEFAULT_SHELL_STATUS_BAR_MODE
  end
end
