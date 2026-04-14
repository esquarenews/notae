class Block < ApplicationRecord
  include PgSearch::Model

  POSITION_GAP = 1024
  DEFAULT_CONTENT = { "type" => "doc", "content" => [ { "type" => "paragraph" } ] }.freeze
  EMBED_ALLOWLIST = %w[
    youtube.com
    www.youtube.com
    youtu.be
    vimeo.com
    player.vimeo.com
    figma.com
    www.figma.com
    loom.com
    www.loom.com
  ].freeze

  has_paper_trail

  belongs_to :workspace
  belongs_to :page
  belongs_to :parent_block, class_name: "Block", optional: true
  belongs_to :created_by, class_name: "User"

  has_many :child_blocks, -> { order(:position) }, class_name: "Block", foreign_key: :parent_block_id, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :page_links, foreign_key: :source_block_id, dependent: :destroy
  has_one_attached :asset

  validates :block_type, presence: true
  validates :content_json, presence: true
  validates :position, numericality: { greater_than: 0, only_integer: true }
  validates :search_text, presence: true
  validate :validate_embed_domain

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position) }
  scope :roots, -> { where(parent_block_id: nil) }
  scope :for_page, ->(page) { where(page_id: page.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  pg_search_scope :search_full_text,
                  against: %i[search_text block_type],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_page
  before_validation :set_default_content
  before_validation :set_search_text
  before_validation :set_initial_position, on: :create
  after_commit :sync_page_links, if: :sync_links_required?
  after_commit :enqueue_search_chunk_reindex, if: :search_chunk_reindex_required?

  def archiveable_tree_ids
    ids = [ id ]
    frontier = [ id ]

    while frontier.any?
      children = self.class.where(parent_block_id: frontier).pluck(:id)
      ids.concat(children)
      frontier = children
    end

    ids
  end

  def metadata
    content_json.is_a?(Hash) ? content_json : {}
  end

  def color
    metadata["notae_color"].presence
  end

  def highlight_color
    metadata["notae_highlight"].presence
  end

  def synced_source_block_id
    metadata["notae_synced_source_id"].presence
  end

  def gantt_workspace_slug
    metadata["notae_gantt_workspace_slug"].presence
  end

  def gantt_database_id
    metadata["notae_gantt_database_id"].presence
  end

  def gantt_view_id
    metadata["notae_gantt_view_id"].presence
  end

  def graph_workspace_slug
    metadata["notae_graph_workspace_slug"].presence
  end

  def graph_database_id
    metadata["notae_graph_database_id"].presence
  end

  def graph_view_id
    metadata["notae_graph_view_id"].presence
  end

  def layout_columns_count
    count = metadata["notae_columns_count"].to_i
    count.positive? ? count : nil
  end

  def synced_copy?
    synced_source_block_id.present? && synced_source_block_id.to_s != id.to_s
  end

  private

  def set_workspace_from_page
    self.workspace = page.workspace if page.present?
  end

  def set_default_content
    self.content_json = DEFAULT_CONTENT.deep_dup if content_json.blank?
  end

  def set_search_text
    text_nodes = []
    extract_text_nodes(content_json, text_nodes)
    self.search_text = text_nodes.join(" ").strip.presence || block_type.to_s
  end

  def set_initial_position
    return if will_save_change_to_position?

    sibling_max = self.class.active.where(page_id: page_id, parent_block_id: parent_block_id).maximum(:position) || 0
    self.position = sibling_max + POSITION_GAP
  end

  def extract_text_nodes(node, collector)
    case node
    when Hash
      collector << node["text"] if node["text"].is_a?(String)
      node.each do |key, child|
        next if key.to_s.start_with?("notae_")

        extract_text_nodes(child, collector)
      end
    when Array
      node.each { |child| extract_text_nodes(child, collector) }
    end
  end

  def sync_links_required?
    previous_changes.key?("content_json") ||
      previous_changes.key?("archived_at") ||
      previous_changes.key?("page_id")
  end

  def search_chunk_reindex_required?
    previous_changes.key?("content_json") ||
      previous_changes.key?("archived_at") ||
      previous_changes.key?("page_id")
  end

  def sync_page_links
    unless defined?(::PageLinks::SyncFromBlockService)
      load Rails.root.join("app/services/page_links/sync_from_block_service.rb").to_s
    end
    ::PageLinks::SyncFromBlockService.call(block: self)
  end

  def enqueue_search_chunk_reindex
    page_ids = [ page_id, previous_changes.dig("page_id", 0) ].compact.uniq
    page_ids.each do |target_page_id|
      Search::IndexPageJob.perform_later(target_page_id)
    rescue StandardError => error
      raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

      Rails.logger.warn("Search index queue unavailable for page=#{target_page_id}: #{error.class}: #{error.message}")
      fallback_page = Page.find_by(id: target_page_id)
      if fallback_page.present?
        Search::ChunkIndexingService.index_page!(page: fallback_page)
      else
        Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_PAGE, source_id: target_page_id)
      end
    end
  end

  def embed_block?
    block_type.to_s == "embed"
  end

  def media_block?
    %w[image video file].include?(block_type.to_s)
  end

  def asset_image?
    asset.attached? && asset.content_type.to_s.start_with?("image/")
  end

  def asset_video?
    asset.attached? && asset.content_type.to_s.start_with?("video/")
  end

  def extract_embed_host
    URI.parse(embed_url.to_s).host&.downcase
  rescue URI::InvalidURIError
    nil
  end

  def validate_embed_domain
    return unless embed_block?
    return if embed_url.blank?

    host = extract_embed_host
    unless host && EMBED_ALLOWLIST.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }
      errors.add(:embed_url, "is not in the allowlist")
    end
  end
end
