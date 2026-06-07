class User < ApplicationRecord
  SMTP_SETTING_FIELDS = %w[
    smtp_address
    smtp_port
    smtp_domain
    smtp_username
    smtp_password
    smtp_authentication
    smtp_enable_starttls_auto
    smtp_from_name
    smtp_from_email
  ].freeze

  encrypts :openai_api_key
  encrypts :smtp_username
  encrypts :smtp_password

  THEME_OPTIONS = [
    [ "Light", "light" ],
    [ "Use system setting", "system" ],
    [ "Dark", "dark" ]
  ].freeze

  LANGUAGE_OPTIONS = [
    [ "English (US)", "en-US" ],
    [ "English (UK)", "en-GB" ]
  ].freeze

  DATE_FORMAT_OPTIONS = [
    [ "Full date", "full_date" ],
    [ "Short date", "short_date" ],
    [ "Month/Day/Year", "month_day_year" ],
    [ "Day/Month/Year", "day_month_year" ],
    [ "Year/Month/Day", "year_month_day" ],
    [ "Relative", "relative" ]
  ].freeze

  OPEN_ON_START_OPTIONS = [
    [ "Home page", "workspace_home" ],
    [ "Last page visited", "last_visited_page" ]
  ].freeze

  SAAS_PLAN_FREE = "free"
  SAAS_PLAN_STARTER = "starter"
  SAAS_PLAN_TEAM = "team"
  SAAS_PLAN_BUSINESS = "business"
  SAAS_PLAN_KEYS = [
    SAAS_PLAN_FREE,
    SAAS_PLAN_STARTER,
    SAAS_PLAN_TEAM,
    SAAS_PLAN_BUSINESS
  ].freeze
  SAAS_PLAN_NAMES = {
    SAAS_PLAN_FREE => "Free",
    SAAS_PLAN_STARTER => "Starter",
    SAAS_PLAN_TEAM => "Team",
    SAAS_PLAN_BUSINESS => "Business"
  }.freeze
  SAAS_WORKSPACE_LIMITS = {
    SAAS_PLAN_FREE => nil,
    SAAS_PLAN_STARTER => 10,
    SAAS_PLAN_TEAM => 50,
    SAAS_PLAN_BUSINESS => nil
  }.freeze

  START_WEEK_OPTIONS = [
    [ "Monday", "monday" ],
    [ "Sunday", "sunday" ]
  ].freeze

  COOKIE_SETTINGS_OPTIONS = [
    [ "Customize", "customize" ],
    [ "Balanced", "balanced" ],
    [ "Strict", "strict" ]
  ].freeze

  AI_LOADER_STYLE_OPTIONS = [
    [ "Halo Relay", "disco_orbit" ],
    [ "Prism Lattice", "neon_mesh" ],
    [ "Pearl Circuit", "pulse_beads" ],
    [ "Mirror Sweep", "disco_ball_reflect" ],
    [ "Aurora Drift", "flock_cloud" ],
    [ "Synapse Bloom", "neural_network" ],
    [ "Plasma Core", "luminous_pulse_sphere" ],
    [ "Tidal Pulse", "luminous_wave_sphere" ]
  ].freeze

  AI_LOADER_STYLE_DESCRIPTIONS = {
    "disco_orbit" => "A polished orbital relay with slow satellites circling a glassy central pearl.",
    "neon_mesh" => "A crisp geometric lattice with luminous edges and signal pulses running through the frame.",
    "pulse_beads" => "A velvet string of gradient pearls that wakes up in a soft sequenced rhythm.",
    "disco_ball_reflect" => "A mirrored disc with faceted reflections and a clean travelling light sweep.",
    "flock_cloud" => "A drifting cloud of fine motes that feels airy, spatial, and slightly alive.",
    "neural_network" => "An organic synapse cluster with branching links and restrained electric bloom.",
    "luminous_pulse_sphere" => "A dense plasma core with a breathing glow and restrained peripheral sparks.",
    "luminous_wave_sphere" => "A wave-driven energy shell with sweeping arcs that wrap around a bright center."
  }.freeze

  CHANNEL_NOTIFICATION_OPTIONS = [
    [ "Off", "off" ],
    [ "Mentions", "mentions" ],
    [ "All activity", "all_activity" ]
  ].freeze

  PUSH_NOTIFICATION_OPTIONS = [
    {
      param_key: "push_notify_mentions",
      type: Notification::TYPE_MENTION,
      label: "Mentions and comments",
      description: "New mentions and comment activity that needs attention."
    },
    {
      param_key: "push_notify_calendar_reminders",
      type: Notification::TYPE_CALENDAR_REMINDER,
      label: "Calendar reminders",
      description: "Upcoming Kalendārium reminders for events and meetings."
    },
    {
      param_key: "push_notify_approval_requests",
      type: Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
      label: "Approval requests",
      description: "Agent drafts waiting on your approval."
    },
    {
      param_key: "push_notify_changes_requested",
      type: Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED,
      label: "Changes requested",
      description: "Drafts that were sent back for changes."
    },
    {
      param_key: "push_notify_resubmitted_drafts",
      type: Notification::TYPE_AGENT_ACTION_RESUBMITTED,
      label: "Resubmitted drafts",
      description: "Drafts that were updated and re-submitted for review."
    },
    {
      param_key: "push_notify_approved_drafts",
      type: Notification::TYPE_AGENT_ACTION_APPROVED,
      label: "Approved drafts",
      description: "Confirmation that an agent draft was approved."
    },
    {
      param_key: "push_notify_rejected_drafts",
      type: Notification::TYPE_AGENT_ACTION_REJECTED,
      label: "Rejected drafts",
      description: "Confirmation that an agent draft was rejected."
    },
    {
      param_key: "push_notify_workflow_failures",
      type: Notification::TYPE_WORKFLOW_FAILED,
      label: "Workflow failures",
      description: "Critical workflow failures. These bypass quiet hours."
    },
    {
      param_key: "push_notify_ai_suggestions",
      type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      label: "AI suggestions",
      description: "Knowledge suggestions and daily AI briefs that are ready."
    },
    {
      param_key: "push_notify_codex_completions",
      type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      label: "Codex completions",
      description: "Completion pushes sent from Codex into Notae."
    }
  ].freeze
  PUSH_QUIET_HOURS_EXEMPT_TYPES = [ Notification::TYPE_WORKFLOW_FAILED ].freeze
  CLOCK_TIME_PATTERN = /\A([01]\d|2[0-3]):[0-5]\d\z/

  SMTP_AUTHENTICATION_OPTIONS = [
    [ "Plain", "plain" ],
    [ "Login", "login" ],
    [ "CRAM-MD5", "cram_md5" ]
  ].freeze

  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :created_pages, class_name: "Page", foreign_key: :created_by_id, inverse_of: :created_by
  has_many :created_blocks, class_name: "Block", foreign_key: :created_by_id, inverse_of: :created_by
  has_many :page_shares, dependent: :destroy
  has_many :shared_pages, through: :page_shares, source: :page
  has_many :database_shares, dependent: :destroy
  has_many :shared_databases, through: :database_shares, source: :database
  has_many :audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :destroy
  has_many :authored_comments, class_name: "Comment", foreign_key: :author_id, inverse_of: :author
  has_many :resolved_comments, class_name: "Comment", foreign_key: :resolved_by_id, inverse_of: :resolved_by
  has_many :notifications, foreign_key: :recipient_id, inverse_of: :recipient, dependent: :destroy
  has_many :web_push_subscriptions, dependent: :destroy
  has_many :web_push_delivery_attempts, dependent: :destroy
  has_many :triggered_notifications, class_name: "Notification", foreign_key: :actor_id, inverse_of: :actor
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, inverse_of: :invited_by
  has_many :accepted_invitations, class_name: "Invitation", foreign_key: :accepted_by_id, inverse_of: :accepted_by
  has_many :created_share_links, class_name: "ShareLink", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_database_share_links, class_name: "DatabaseShareLink", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_database_shares, class_name: "DatabaseShare", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :created_database_views, class_name: "DatabaseView", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_database_templates, class_name: "DatabaseTemplate", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :requested_page_exports, class_name: "PageExport", foreign_key: :requested_by_id, inverse_of: :requested_by, dependent: :destroy
  has_many :created_page_templates, class_name: "PageTemplate", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_cover_assets, class_name: "WorkspaceCoverAsset", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :api_token_audit_events, dependent: :destroy
  has_many :admin_audit_events, foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify
  has_many :favorites, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_many :ai_conversations, dependent: :destroy
  has_many :knowledge_suggestions, dependent: :destroy
  has_many :workflow_runs, dependent: :destroy
  has_many :kalendarium_connections, as: :owner, dependent: :destroy
  has_many :created_kalendarium_connections, class_name: "KalendariumConnection", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_kalendarium_calendars, class_name: "KalendariumCalendar", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_kalendarium_projects, class_name: "KalendariumProject", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :created_kalendarium_events, class_name: "KalendariumEvent", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :updated_kalendarium_events, class_name: "KalendariumEvent", foreign_key: :updated_by_id, inverse_of: :updated_by, dependent: :destroy
  has_many :kalendarium_write_proposals, dependent: :destroy
  has_many :created_meeting_sessions, class_name: "MeetingSession", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :updated_meeting_sessions, class_name: "MeetingSession", foreign_key: :updated_by_id, inverse_of: :updated_by, dependent: :destroy
  has_one_attached :avatar

  # Include default devise modules. Others available are:
  # :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable, :lockable,
         :recoverable, :rememberable, :validatable

  attr_accessor :self_service_registration_confirmation_required, :website

  before_validation :skip_confirmation_for_internal_create, on: :create

  validates :theme_preference, inclusion: { in: THEME_OPTIONS.map(&:last) }
  validates :language_preference, inclusion: { in: LANGUAGE_OPTIONS.map(&:last) }
  validates :date_format_preference, inclusion: { in: DATE_FORMAT_OPTIONS.map(&:last) }
  validates :open_on_start_preference, inclusion: { in: OPEN_ON_START_OPTIONS.map(&:last) }
  validates :cookie_settings_preference, inclusion: { in: COOKIE_SETTINGS_OPTIONS.map(&:last) }
  validates :ai_loader_style, inclusion: { in: AI_LOADER_STYLE_OPTIONS.map(&:last) }
  validates :show_text_direction_controls, inclusion: { in: [ true, false ] }
  validates :start_week_on_monday, inclusion: { in: [ true, false ] }
  validates :auto_time_zone, inclusion: { in: [ true, false ] }
  validates :open_links_in_desktop_app, inclusion: { in: [ true, false ] }
  validates :reduce_ai_loader_motion, inclusion: { in: [ true, false ] }
  validates :show_view_history, inclusion: { in: [ true, false ] }
  validates :profile_discoverability, inclusion: { in: [ true, false ] }
  validates :meeting_notify_join_transcribing, inclusion: { in: [ true, false ] }
  validates :meeting_notify_transcribed, inclusion: { in: [ true, false ] }
  validates :meeting_notify_summarized, inclusion: { in: [ true, false ] }
  validates :push_quiet_hours_enabled, inclusion: { in: [ true, false ] }, if: -> { self.class.column_names.include?("push_quiet_hours_enabled") }
  validates :email_notify_activity, inclusion: { in: [ true, false ] }
  validates :email_notify_always_send, inclusion: { in: [ true, false ] }
  validates :email_notify_page_updates, inclusion: { in: [ true, false ] }
  validates :email_notify_workspace_digest, inclusion: { in: [ true, false ] }
  validates :slack_notification_preference, inclusion: { in: CHANNEL_NOTIFICATION_OPTIONS.map(&:last) }
  validates :discord_notification_preference, inclusion: { in: CHANNEL_NOTIFICATION_OPTIONS.map(&:last) }
  validates :push_quiet_hours_starts_at, format: { with: CLOCK_TIME_PATTERN }, if: -> { self.class.column_names.include?("push_quiet_hours_starts_at") }
  validates :push_quiet_hours_ends_at, format: { with: CLOCK_TIME_PATTERN }, if: -> { self.class.column_names.include?("push_quiet_hours_ends_at") }
  validates :openai_api_key, length: { maximum: 255 }, allow_blank: true
  validates :saas_plan_key, inclusion: { in: SAAS_PLAN_KEYS }
  validates :workspace_limit_override,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            allow_nil: true
  validates :smtp_address, length: { maximum: 255 }, allow_blank: true
  validates :full_name, length: { maximum: 120 }, allow_blank: true
  validates :backup_email, length: { maximum: 255 }, allow_blank: true
  validates :backup_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :personal_bio, length: { maximum: 1000 }, allow_blank: true
  validates :smtp_domain, length: { maximum: 255 }, allow_blank: true
  validates :smtp_username, length: { maximum: 255 }, allow_blank: true
  validates :smtp_password, length: { maximum: 255 }, allow_blank: true
  validates :smtp_from_name, length: { maximum: 255 }, allow_blank: true
  validates :smtp_from_email, length: { maximum: 255 }, allow_blank: true
  validates :smtp_port,
            numericality: {
              only_integer: true,
              greater_than: 0,
              less_than_or_equal_to: 65_535
            },
            allow_nil: true
  validates :smtp_authentication, inclusion: { in: SMTP_AUTHENTICATION_OPTIONS.map(&:last) }
  validate :smtp_settings_complete_if_any
  validate :smtp_address_is_public
  validate :smtp_from_email_format
  validate :push_notification_preferences_supported
  validates :ai_search_daily_budget_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :ai_search_semantic_rate_limit_per_minute, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :ai_search_answer_rate_limit_per_minute, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :time_zone, presence: true
  validate :time_zone_supported
  validate :calendar_extra_time_zones_supported

  def self.time_zone_options
    ActiveSupport::TimeZone.all.map { |zone| [ "(GMT#{zone.formatted_offset}) #{zone.name}", zone.name ] }
  end

  def self.platform_admin_email_allowlisted?(email_address)
    platform_admin_email_allowlist.include?(email_address.to_s.downcase)
  end

  def self.platform_admin_email_allowlist
    ENV.fetch("NOTAE_PLATFORM_ADMIN_EMAILS", "")
       .split(",")
       .map { |email_address| email_address.strip.downcase }
       .reject(&:blank?)
  end

  def require_self_service_registration_confirmation!
    self.self_service_registration_confirmation_required = true
  end

  def start_week_preference
    start_week_on_monday? ? "monday" : "sunday"
  end

  def display_name
    full_name.to_s.strip.presence || email.to_s
  end

  def saas_plan_name
    SAAS_PLAN_NAMES.fetch(saas_plan_key, saas_plan_key.to_s.humanize)
  end

  def workspace_limit
    return workspace_limit_override if workspace_limit_override.present? || workspace_limit_override == 0

    SAAS_WORKSPACE_LIMITS.fetch(saas_plan_key)
  end

  def workspace_limit_unlimited?
    workspace_limit.nil?
  end

  def workspace_limit_label
    workspace_limit_unlimited? ? "Unlimited" : workspace_limit.to_s
  end

  def platform_admin?
    super_admin? || platform_admin_email_allowlisted?
  end

  def avatar_initials
    name = display_name.to_s.strip
    return email.to_s.first.to_s.upcase if name.blank?

    initials = name.split(/\s+/).filter_map { |part| part.first&.upcase }.first(2).join
    initials.presence || email.to_s.first.to_s.upcase
  end

  def account_deletion_recipients
    [ email, backup_email.presence ].compact.uniq
  end

  def openai_api_key_configured?
    encrypted_value_present?(:openai_api_key)
  end

  def masked_openai_api_key
    return "Not configured" unless openai_api_key_configured?
    value = safe_encrypted_value(:openai_api_key)
    return "Not configured" if value.blank?

    "#{value.first(6)}...#{value.last(4)}"
  end

  def smtp_configured?
    smtp_address.present? &&
      smtp_port.present? &&
      smtp_username.present? &&
      encrypted_value_present?(:smtp_password) &&
      smtp_from_email.present?
  end

  def masked_smtp_password
    value = safe_encrypted_value(:smtp_password)
    return "Not configured" if value.blank?

    "#{value.first(2)}...#{value.last(2)}"
  end

  def smtp_from_display
    from_email = smtp_from_email.to_s.strip
    from_name = smtp_from_name.to_s.strip
    return from_email if from_name.blank?

    "#{from_name} <#{from_email}>"
  end

  def self.ai_loader_label_for(value)
    AI_LOADER_STYLE_OPTIONS.find { |(_label, option_value)| option_value == value }&.first || AI_LOADER_STYLE_OPTIONS.first.first
  end

  def self.push_notification_param_keys
    PUSH_NOTIFICATION_OPTIONS.map { |option| option[:param_key].to_sym }
  end

  def self.push_notification_type_for_param(param_key)
    PUSH_NOTIFICATION_OPTIONS.find { |option| option[:param_key] == param_key.to_s }&.dig(:type)
  end

  def self.push_notification_types
    PUSH_NOTIFICATION_OPTIONS.map { |option| option[:type].to_s }
  end

  def resolved_ai_search_daily_budget_usd
    ai_search_daily_budget_usd.to_f
  end

  def resolved_ai_search_semantic_rate_limit_per_minute
    ai_search_semantic_rate_limit_per_minute.to_i
  end

  def resolved_ai_search_answer_rate_limit_per_minute
    ai_search_answer_rate_limit_per_minute.to_i
  end

  def calendar_extra_time_zone_list
    Array(calendar_extra_time_zones).map(&:to_s).reject(&:blank?).uniq
  end

  def push_notification_preferences
    return {} unless self.class.column_names.include?("push_notification_preferences")

    raw_preferences = self[:push_notification_preferences]
    raw_preferences.is_a?(Hash) ? raw_preferences : {}
  end

  def push_quiet_hours_enabled?
    return false unless self.class.column_names.include?("push_quiet_hours_enabled")

    ActiveModel::Type::Boolean.new.cast(self[:push_quiet_hours_enabled])
  end

  def push_quiet_hours_starts_at
    return "22:00" unless self.class.column_names.include?("push_quiet_hours_starts_at")

    self[:push_quiet_hours_starts_at].to_s.presence || "22:00"
  end

  def push_quiet_hours_ends_at
    return "07:00" unless self.class.column_names.include?("push_quiet_hours_ends_at")

    self[:push_quiet_hours_ends_at].to_s.presence || "07:00"
  end

  def push_notification_enabled_for?(notification_type, workspace: nil, membership: nil)
    stored_value = push_notification_preferences[notification_type.to_s]
    global_default = stored_value.nil? ? true : ActiveModel::Type::Boolean.new.cast(stored_value)
    scoped_membership = membership || membership_for_notification_workspace(workspace)
    return global_default if scoped_membership.blank?

    scoped_membership.workspace_push_notification_enabled?(notification_type, default: global_default)
  end

  def push_quiet_hours_active_for?(notification_type = nil, at: Time.current)
    return false unless push_quiet_hours_enabled?
    return false if notification_type.present? && PUSH_QUIET_HOURS_EXEMPT_TYPES.include?(notification_type.to_s)

    start_minutes = clock_string_to_minutes(push_quiet_hours_starts_at)
    end_minutes = clock_string_to_minutes(push_quiet_hours_ends_at)
    return false if start_minutes.nil? || end_minutes.nil? || start_minutes == end_minutes

    local_time = at.in_time_zone(ActiveSupport::TimeZone[time_zone] || Time.zone)
    minute_of_day = (local_time.hour * 60) + local_time.min

    if start_minutes < end_minutes
      minute_of_day >= start_minutes && minute_of_day < end_minutes
    else
      minute_of_day >= start_minutes || minute_of_day < end_minutes
    end
  end

  def push_delivery_allowed_for?(notification_type, workspace: nil, membership: nil, at: Time.current)
    push_notification_enabled_for?(notification_type, workspace: workspace, membership: membership) &&
      !push_quiet_hours_active_for?(notification_type, at: at)
  end

  def email_notify_activity_for?(workspace, membership: nil)
    scoped_membership = membership || membership_for_notification_workspace(workspace)
    return email_notify_activity? if scoped_membership.blank?

    scoped_membership.workspace_email_notify_activity_enabled?(default: email_notify_activity?)
  end

  private

  def skip_confirmation_for_internal_create
    return unless respond_to?(:skip_confirmation!)
    return if self_service_registration_confirmation_required

    skip_confirmation!
  end

  def time_zone_supported
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not supported")
  end

  def smtp_settings_complete_if_any
    return unless smtp_settings_started?
    return unless smtp_settings_change_submitted?

    errors.add(:smtp_address, "can't be blank") if smtp_address.blank?
    errors.add(:smtp_port, "can't be blank") if smtp_port.blank?
    errors.add(:smtp_username, "can't be blank") if smtp_username.blank?
    errors.add(:smtp_password, "can't be blank") if smtp_password.blank?
    errors.add(:smtp_from_email, "can't be blank") if smtp_from_email.blank?
  end

  def smtp_from_email_format
    return if smtp_from_email.blank?
    return if smtp_from_email.match?(Devise.email_regexp)

    errors.add(:smtp_from_email, "is invalid")
  end

  def smtp_address_is_public
    return if smtp_address.blank?
    return if Notae::OutboundNetworkGuard.public_host?(smtp_address)

    errors.add(:smtp_address, "must use a public host")
  end

  def smtp_settings_started?
    [
      smtp_address,
      smtp_port,
      smtp_domain,
      smtp_username,
      safe_encrypted_value(:smtp_password),
      smtp_from_name,
      smtp_from_email
    ].any?(&:present?)
  end

  def smtp_settings_change_submitted?
    SMTP_SETTING_FIELDS.any? { |field| will_save_change_to_attribute?(field) } ||
      smtp_password.to_s.present?
  end

  def calendar_extra_time_zones_supported
    invalid_time_zones = calendar_extra_time_zone_list.reject { |zone_name| ActiveSupport::TimeZone[zone_name].present? }
    return if invalid_time_zones.empty?

    errors.add(:calendar_extra_time_zones, "contains unsupported time zones")
  end

  def push_notification_preferences_supported
    return unless self.class.column_names.include?("push_notification_preferences")

    unsupported_keys = push_notification_preferences.keys.map(&:to_s) - self.class.push_notification_types
    return if unsupported_keys.empty?

    errors.add(:push_notification_preferences, "contains unsupported notification types")
  end

  def membership_for_notification_workspace(workspace)
    workspace_id = workspace.is_a?(Workspace) ? workspace.id : workspace

    if memberships.loaded?
      memberships.find { |membership| membership.workspace_id == workspace_id }
    else
      memberships.find_by(workspace_id: workspace_id)
    end
  end

  def platform_admin_email_allowlisted?
    self.class.platform_admin_email_allowlisted?(email)
  end

  def clock_string_to_minutes(raw_value)
    value = raw_value.to_s
    return nil unless CLOCK_TIME_PATTERN.match?(value)

    hours, minutes = value.split(":").map(&:to_i)
    (hours * 60) + minutes
  end

  def encrypted_value_present?(attribute_name)
    safe_encrypted_value(attribute_name).present?
  end

  def safe_encrypted_value(attribute_name)
    public_send(attribute_name)
  rescue ActiveRecord::Encryption::Errors::Configuration => error
    log_encryption_configuration_error(attribute_name, error)
    nil
  end

  def log_encryption_configuration_error(attribute_name, error)
    Rails.logger.error(
      "[EncryptionConfig] Missing key while reading User##{attribute_name}: #{error.message}"
    )
  end
end
