class Page < ApplicationRecord
  include PgSearch::Model
  include IconTokenSupport

  has_paper_trail
  ORIGINAL_COVER_PRESETS = %w[
    aurora-dunes
    basalt-ink
    citrus-wave
    dawn-grid
    neon-tiles
    coral-bloom
    midnight-fog
    mono-mist
    sunset-ribbon
    emerald-fade
    prism-burst
    graphite-strata
  ].map { |key| { key: key, label: key.humanize, kind: :asset } }.freeze
  VECTOR_COVER_PRESETS = [
    { key: "vector-arcade-sun", label: "Arcade Sun", kind: :style, background: "linear-gradient(135deg, #0f172a 0%, #1e293b 46%, #f97316 46%, #fb7185 68%, #f8fafc 68%, #f8fafc 100%), radial-gradient(circle at 22% 26%, rgba(251, 191, 36, 0.95) 0 10%, transparent 10.5%), repeating-linear-gradient(90deg, rgba(255,255,255,0.14) 0 2px, transparent 2px 22px)" },
    { key: "vector-atlas-lines", label: "Atlas Lines", kind: :style, background: "linear-gradient(125deg, #e0f2fe 0%, #bae6fd 50%, #0f172a 50%, #0f172a 100%), linear-gradient(90deg, rgba(15, 23, 42, 0.22) 0 1px, transparent 1px 18px), linear-gradient(0deg, rgba(15, 23, 42, 0.18) 0 1px, transparent 1px 18px)" },
    { key: "vector-brass-sun", label: "Brass Sun", kind: :style, background: "linear-gradient(145deg, #fafaf9 0%, #fafaf9 38%, #facc15 38%, #ca8a04 70%, #422006 100%), radial-gradient(circle at 78% 28%, rgba(255,255,255,0.82) 0 14%, transparent 14.5%), linear-gradient(25deg, transparent 0 55%, rgba(0,0,0,0.18) 55% 100%)" },
    { key: "vector-drift-paper", label: "Drift Paper", kind: :style, background: "linear-gradient(135deg, #fdf2f8 0%, #fdf2f8 48%, #d946ef 48%, #8b5cf6 100%), radial-gradient(circle at 26% 24%, rgba(255,255,255,0.86) 0 16%, transparent 16.5%), linear-gradient(155deg, rgba(255,255,255,0.32) 0 32%, transparent 32% 100%)" },
    { key: "vector-harbor-shapes", label: "Harbor Shapes", kind: :style, background: "linear-gradient(160deg, #082f49 0%, #0c4a6e 40%, #38bdf8 40%, #e0f2fe 100%), linear-gradient(25deg, transparent 0 58%, rgba(255,255,255,0.22) 58% 72%, transparent 72% 100%), radial-gradient(circle at 18% 76%, rgba(250,204,21,0.9) 0 11%, transparent 11.5%)" },
    { key: "vector-kinetic-sky", label: "Kinetic Sky", kind: :style, background: "linear-gradient(135deg, #312e81 0%, #4338ca 50%, #60a5fa 50%, #e0f2fe 100%), repeating-linear-gradient(135deg, rgba(255,255,255,0.16) 0 10px, transparent 10px 28px), radial-gradient(circle at 72% 24%, rgba(255,255,255,0.78) 0 12%, transparent 12.5%)" },
    { key: "vector-mosaic-loop", label: "Mosaic Loop", kind: :style, background: "linear-gradient(135deg, #111827 0%, #111827 34%, #22c55e 34%, #86efac 62%, #fef3c7 62%, #f97316 100%), linear-gradient(90deg, rgba(255,255,255,0.16) 0 3px, transparent 3px 26px), linear-gradient(0deg, rgba(255,255,255,0.14) 0 3px, transparent 3px 26px)" },
    { key: "vector-orbit-bloom", label: "Orbit Bloom", kind: :style, background: "linear-gradient(140deg, #ecfeff 0%, #cffafe 38%, #14b8a6 38%, #0f766e 100%), radial-gradient(circle at 24% 34%, rgba(244,114,182,0.92) 0 14%, transparent 14.5%), radial-gradient(circle at 71% 65%, rgba(250,204,21,0.88) 0 12%, transparent 12.5%)" },
    { key: "vector-paper-kites", label: "Paper Kites", kind: :style, background: "linear-gradient(125deg, #fff7ed 0%, #fed7aa 45%, #fb7185 45%, #be185d 100%), linear-gradient(35deg, transparent 0 48%, rgba(255,255,255,0.22) 48% 54%, transparent 54% 100%), linear-gradient(145deg, transparent 0 58%, rgba(255,255,255,0.16) 58% 64%, transparent 64% 100%)" },
    { key: "vector-signal-hills", label: "Signal Hills", kind: :style, background: "linear-gradient(160deg, #052e16 0%, #166534 44%, #4ade80 44%, #dcfce7 100%), radial-gradient(circle at 82% 24%, rgba(250,204,21,0.88) 0 11%, transparent 11.5%), linear-gradient(0deg, rgba(255,255,255,0.14) 0 2px, transparent 2px 20px)" },
    { key: "vector-tide-arcs", label: "Tide Arcs", kind: :style, background: "linear-gradient(135deg, #0f172a 0%, #1d4ed8 48%, #38bdf8 48%, #e0f2fe 100%), radial-gradient(circle at 26% 82%, rgba(255,255,255,0.24) 0 18%, transparent 18.5%), radial-gradient(circle at 68% 18%, rgba(251,146,60,0.86) 0 12%, transparent 12.5%)" },
    { key: "vector-window-garden", label: "Window Garden", kind: :style, background: "linear-gradient(135deg, #f0fdf4 0%, #dcfce7 45%, #16a34a 45%, #14532d 100%), linear-gradient(90deg, rgba(255,255,255,0.18) 0 4px, transparent 4px 28px), linear-gradient(180deg, transparent 0 58%, rgba(253,224,71,0.82) 58% 100%)" }
  ].freeze
  PASTEL_COVER_PRESETS = [
    { key: "pastel-apricot", label: "Apricot", kind: :style, background: "#f8d7be" },
    { key: "pastel-blush", label: "Blush", kind: :style, background: "#f4cbd6" },
    { key: "pastel-cloud", label: "Cloud", kind: :style, background: "#e7ecf5" },
    { key: "pastel-lavender", label: "Lavender", kind: :style, background: "#ddd4f7" },
    { key: "pastel-mint", label: "Mint", kind: :style, background: "#d5efe4" },
    { key: "pastel-peach", label: "Peach", kind: :style, background: "#f6d4c3" },
    { key: "pastel-periwinkle", label: "Periwinkle", kind: :style, background: "#cfd7fb" },
    { key: "pastel-petal", label: "Petal", kind: :style, background: "#f7dceb" },
    { key: "pastel-sage", label: "Sage", kind: :style, background: "#d9e2c7" },
    { key: "pastel-sky", label: "Sky", kind: :style, background: "#d6ebfa" },
    { key: "pastel-sun", label: "Sun", kind: :style, background: "#f9ecba" },
    { key: "pastel-seafoam", label: "Seafoam", kind: :style, background: "#cbe9df" }
  ].freeze
  BOLD_COVER_PRESETS = [
    { key: "bold-cobalt", label: "Cobalt", kind: :style, background: "#1d4ed8" },
    { key: "bold-coral", label: "Coral", kind: :style, background: "#f97360" },
    { key: "bold-crimson", label: "Crimson", kind: :style, background: "#be123c" },
    { key: "bold-emerald", label: "Emerald", kind: :style, background: "#059669" },
    { key: "bold-fuchsia", label: "Fuchsia", kind: :style, background: "#c026d3" },
    { key: "bold-indigo", label: "Indigo", kind: :style, background: "#4338ca" },
    { key: "bold-mango", label: "Mango", kind: :style, background: "#f59e0b" },
    { key: "bold-onyx", label: "Onyx", kind: :style, background: "#18181b" },
    { key: "bold-scarlet", label: "Scarlet", kind: :style, background: "#dc2626" },
    { key: "bold-teal", label: "Teal", kind: :style, background: "#0f766e" },
    { key: "bold-ultraviolet", label: "Ultraviolet", kind: :style, background: "#7c3aed" },
    { key: "bold-vermilion", label: "Vermilion", kind: :style, background: "#ea580c" }
  ].freeze
  GRADIENT_COVER_PRESETS = [
    { key: "gradient-amber-sky", label: "Amber Sky", kind: :style, background: "linear-gradient(135deg, #fbbf24 0%, #fb7185 100%)" },
    { key: "gradient-aqua-dusk", label: "Aqua Dusk", kind: :style, background: "linear-gradient(135deg, #22d3ee 0%, #2563eb 100%)" },
    { key: "gradient-berry-glow", label: "Berry Glow", kind: :style, background: "linear-gradient(135deg, #f472b6 0%, #7c3aed 100%)" },
    { key: "gradient-candy-flare", label: "Candy Flare", kind: :style, background: "linear-gradient(135deg, #fb7185 0%, #f97316 52%, #facc15 100%)" },
    { key: "gradient-citrus-pop", label: "Citrus Pop", kind: :style, background: "linear-gradient(135deg, #84cc16 0%, #facc15 52%, #f97316 100%)" },
    { key: "gradient-cosmos", label: "Cosmos", kind: :style, background: "linear-gradient(135deg, #0f172a 0%, #4338ca 45%, #ec4899 100%)" },
    { key: "gradient-electric-mint", label: "Electric Mint", kind: :style, background: "linear-gradient(135deg, #34d399 0%, #06b6d4 55%, #2563eb 100%)" },
    { key: "gradient-ember-wave", label: "Ember Wave", kind: :style, background: "linear-gradient(135deg, #f97316 0%, #dc2626 52%, #7f1d1d 100%)" },
    { key: "gradient-lagoon", label: "Lagoon", kind: :style, background: "linear-gradient(135deg, #06b6d4 0%, #14b8a6 52%, #0f766e 100%)" },
    { key: "gradient-molten-dawn", label: "Molten Dawn", kind: :style, background: "linear-gradient(135deg, #f59e0b 0%, #ef4444 52%, #7c2d12 100%)" },
    { key: "gradient-rose-storm", label: "Rose Storm", kind: :style, background: "linear-gradient(135deg, #f9a8d4 0%, #e11d48 52%, #312e81 100%)" },
    { key: "gradient-violet-haze", label: "Violet Haze", kind: :style, background: "linear-gradient(135deg, #818cf8 0%, #8b5cf6 52%, #c026d3 100%)" }
  ].freeze
  COVER_PRESET_GROUPS = [
    { key: "original", label: "Original", presets: ORIGINAL_COVER_PRESETS },
    { key: "vector", label: "Vector", presets: VECTOR_COVER_PRESETS },
    { key: "pastel", label: "Pastel", presets: PASTEL_COVER_PRESETS },
    { key: "bold", label: "Bold", presets: BOLD_COVER_PRESETS },
    { key: "gradient", label: "Gradient", presets: GRADIENT_COVER_PRESETS }
  ].freeze
  COVER_PRESET_KEYS = COVER_PRESET_GROUPS.flat_map { |group| group.fetch(:presets).map { |preset| preset.fetch(:key) } }.freeze
  COVER_PRESET_LOOKUP = COVER_PRESET_GROUPS
                        .flat_map { |group| group.fetch(:presets) }
                        .each_with_object({}) { |preset, lookup| lookup[preset.fetch(:key)] = preset }
                        .freeze
  FONT_STYLES = %w[default serif mono].freeze
  PAGE_KINDS = %w[nota meeting_note].freeze
  ICON_SUGGESTIONS = %w[📄 ✨ 🧠 📝 📌 🧭 🚀 🗂️ 🌿 🌅].freeze
  TAB_COLOR_OPTIONS = [
    [ "Default", "default" ],
    [ "Slate", "slate" ],
    [ "Blue", "blue" ],
    [ "Green", "green" ],
    [ "Amber", "amber" ],
    [ "Rose", "rose" ],
    [ "Purple", "purple" ]
  ].freeze
  TAB_COLOR_KEYS = TAB_COLOR_OPTIONS.map(&:last).freeze
  DEFAULT_ROOT_TAB_TITLE = "Tab 1".freeze

  attribute :permission_mode, :integer, default: 0
  enum :permission_mode, { shared_to_workspace: 0, private_page: 1, specific_users: 2 }, default: :shared_to_workspace

  belongs_to :workspace
  belongs_to :parent_page, class_name: "Page", optional: true
  belongs_to :created_by, class_name: "User"

  has_many :child_pages, -> { order(:created_at) }, class_name: "Page", foreign_key: :parent_page_id, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :page_shares, dependent: :destroy
  has_many :page_presences, dependent: :destroy
  has_many :page_exports, dependent: :destroy
  has_many :page_templates, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :favorites, as: :favoritable, dependent: :destroy
  has_many :search_chunks, dependent: :destroy
  has_many :ai_conversations, dependent: :nullify
  has_many :kalendarium_events, foreign_key: :linked_page_id, dependent: :nullify
  has_many :kalendarium_projects, foreign_key: :linked_page_id, dependent: :nullify
  has_many :shared_users, through: :page_shares, source: :user
  has_many :outgoing_page_links, class_name: "PageLink", foreign_key: :source_page_id, dependent: :destroy
  has_many :incoming_page_links, class_name: "PageLink", foreign_key: :target_page_id, dependent: :destroy
  has_many :meeting_sessions, dependent: :nullify
  has_one_attached :cover_image
  has_one :linked_database, class_name: "Database", foreign_key: :linked_page_id, inverse_of: :linked_page

  validates :title, presence: true
  validates :root_tab_title, length: { maximum: 255 }, allow_blank: true
  validates :page_kind, inclusion: { in: PAGE_KINDS }
  validates :font_style, inclusion: { in: FONT_STYLES }
  validates :tab_color, inclusion: { in: TAB_COLOR_KEYS }
  validates :cover_preset_key, inclusion: { in: COVER_PRESET_KEYS }, allow_blank: true
  validates :cover_focal_y,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :small_text, inclusion: { in: [ true, false ] }
  validates :full_width, inclusion: { in: [ true, false ] }
  validates :remove_blocks, inclusion: { in: [ true, false ] }
  validates :locked, inclusion: { in: [ true, false ] }
  validates :suggest_edits, inclusion: { in: [ true, false ] }
  validate :parent_page_workspace_matches

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :meeting_notes, -> { where(page_kind: "meeting_note") }
  scope :top_level, -> { where(parent_page_id: nil) }
  scope :standalone_top_level, -> { top_level.where.missing(:linked_database) }
  scope :excluding_top_level_linked_database_shells, -> {
    left_outer_joins(:linked_database).where("pages.parent_page_id IS NOT NULL OR databases.id IS NULL")
  }

  pg_search_scope :search_full_text,
                  against: :title,
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_parent, if: -> { workspace_id.nil? && parent_page.present? }
  before_validation :normalize_root_tab_title
  before_validation :normalize_icon
  after_commit :enqueue_search_chunk_reindex, on: :create
  after_commit :enqueue_search_chunk_reindex, on: :update, if: :search_chunk_reindex_required?
  after_commit :remove_search_chunks, on: :destroy

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

  def cover?
    cover_image.attached? || cover_preset_key.present? || cover_remote_url.present?
  end

  def archived?
    archived_at.present?
  end

  def tab_child?
    parent_page_id.present?
  end

  def root_tab?
    parent_page_id.blank?
  end

  def effective_tab_title
    return title if tab_child?

    root_tab_title.presence || DEFAULT_ROOT_TAB_TITLE
  end

  def tab_reference_title
    return title unless tab_child?

    parent_title = parent_page&.title.presence
    return title if parent_title.blank?

    "#{parent_title} / #{title}"
  end

  def cover_remote?
    cover_remote_url.present?
  end

  def search_source_text
    block_text = blocks.active.ordered.with_attached_asset.map(&:searchable_content).join("\n")
    [ title, block_text ].join("\n").squish
  end

  class << self
    def cover_preset_definition(key)
      COVER_PRESET_LOOKUP[key.to_s]
    end

    def cover_preset_group_index(key)
      normalized_key = key.to_s
      COVER_PRESET_GROUPS.index do |group|
        group.fetch(:presets).any? { |preset| preset.fetch(:key) == normalized_key }
      end || 0
    end

    def asset_cover_preset_keys
      ORIGINAL_COVER_PRESETS.map { |preset| preset.fetch(:key) }
    end
  end

  private

  def set_workspace_from_parent
    self.workspace = parent_page.workspace
  end

  def normalize_root_tab_title
    self.root_tab_title = root_tab_title.to_s.strip.presence
  end

  def normalize_icon
    self.icon = normalize_icon_token(icon)
  end

  def parent_page_workspace_matches
    return if parent_page.blank?
    return if parent_page.workspace_id == workspace_id

    errors.add(:parent_page_id, "must belong to the same workspace")
  end

  def enqueue_search_chunk_reindex
    Search::IndexPageJob.perform_later(id)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    Rails.logger.warn("Search index queue unavailable for page=#{id}: #{error.class}: #{error.message}")
    Search::ChunkIndexingService.index_page!(page: self)
  end

  def search_chunk_reindex_required?
    previous_changes.key?("title") ||
      previous_changes.key?("archived_at") ||
      previous_changes.key?("workspace_id")
  end

  def remove_search_chunks
    Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_PAGE, source_id: id)
  end
end
