class User < ApplicationRecord
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
    [ "Disco Orbit", "disco_orbit" ],
    [ "Neon Mesh", "neon_mesh" ],
    [ "Pulse Beads", "pulse_beads" ],
    [ "Disco Ball Reflect", "disco_ball_reflect" ],
    [ "Flock Cloud", "flock_cloud" ],
    [ "Neural Network", "neural_network" ],
    [ "Luminous Pulse Sphere", "luminous_pulse_sphere" ],
    [ "Luminous Wave Sphere", "luminous_wave_sphere" ]
  ].freeze

  AI_LOADER_STYLE_DESCRIPTIONS = {
    "disco_orbit" => "A disco-inspired orbital field with neon cyan/magenta halos.",
    "neon_mesh" => "A connected node mesh that feels like an active neural network.",
    "pulse_beads" => "A ring of beads that softly pulses and rotates in sync.",
    "disco_ball_reflect" => "A spinning disco sphere with mirrored facets and moving light reflections.",
    "flock_cloud" => "A cloud of pink-purple-blue dots that drifts like a flock in formation.",
    "neural_network" => "A futuristic network visualization with connected blue, pink, and purple nodes.",
    "luminous_pulse_sphere" => "A dense luminous particle sphere with cyan-magenta pulses and a glowing energy core.",
    "luminous_wave_sphere" => "A reactive plasma sphere where particle waves wrap and sweep around the core."
  }.freeze

  CHANNEL_NOTIFICATION_OPTIONS = [
    [ "Off", "off" ],
    [ "Mentions", "mentions" ],
    [ "All activity", "all_activity" ]
  ].freeze

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
  has_many :favorites, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy
  has_many :ai_conversations, dependent: :destroy

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

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
  validates :email_notify_activity, inclusion: { in: [ true, false ] }
  validates :email_notify_always_send, inclusion: { in: [ true, false ] }
  validates :email_notify_page_updates, inclusion: { in: [ true, false ] }
  validates :email_notify_workspace_digest, inclusion: { in: [ true, false ] }
  validates :slack_notification_preference, inclusion: { in: CHANNEL_NOTIFICATION_OPTIONS.map(&:last) }
  validates :discord_notification_preference, inclusion: { in: CHANNEL_NOTIFICATION_OPTIONS.map(&:last) }
  validates :openai_api_key, length: { maximum: 255 }, allow_blank: true
  validates :ai_search_daily_budget_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :ai_search_semantic_rate_limit_per_minute, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :ai_search_answer_rate_limit_per_minute, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :time_zone, presence: true
  validate :time_zone_supported

  def self.time_zone_options
    ActiveSupport::TimeZone.all.map { |zone| [ "(GMT#{zone.formatted_offset}) #{zone.name}", zone.name ] }
  end

  def start_week_preference
    start_week_on_monday? ? "monday" : "sunday"
  end

  def openai_api_key_configured?
    openai_api_key.present?
  end

  def masked_openai_api_key
    return "Not configured" unless openai_api_key_configured?

    "#{openai_api_key.first(6)}...#{openai_api_key.last(4)}"
  end

  def self.ai_loader_label_for(value)
    AI_LOADER_STYLE_OPTIONS.find { |(_label, option_value)| option_value == value }&.first || AI_LOADER_STYLE_OPTIONS.first.first
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

  private

  def time_zone_supported
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not supported")
  end
end
