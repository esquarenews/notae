class EpistulariumMessage < ApplicationRecord
  include PgSearch::Model

  MAILBOXES = %w[inbox sent].freeze
  SEARCH_REINDEX_CHANGE_KEYS = %w[
    subject
    from_name
    from_email
    to_recipients_json
    cc_recipients_json
    bcc_recipients_json
    reply_to_recipients_json
    sent_at
    received_at
    unread
    body_text
    body_html
    snippet
    thread_key
  ].freeze

  belongs_to :workspace
  belongs_to :epistularium_account, touch: true

  has_many :search_chunks, dependent: :destroy

  validates :provider_message_id, presence: true
  validates :mailbox, inclusion: { in: MAILBOXES }
  validates :subject, length: { maximum: 300 }

  pg_search_scope :search_full_text,
                  against: %i[subject snippet body_text from_name from_email],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_account, ->(account) { where(epistularium_account_id: account.id) }
  scope :for_mailbox, ->(mailbox) { where(mailbox: mailbox.to_s == "sent" ? "sent" : "inbox") }
  scope :recent_first, -> do
    order(Arel.sql("COALESCE(epistularium_messages.received_at, epistularium_messages.sent_at, epistularium_messages.created_at) DESC"))
  end

  before_validation :normalize_message_fields
  after_commit :enqueue_search_chunk_reindex, on: %i[create update], if: :search_chunk_reindex_required?
  after_commit :remove_search_chunks, on: :destroy

  def display_subject
    subject.to_s.strip.presence || "(no subject)"
  end

  def primary_timestamp
    received_at || sent_at || created_at
  end

  def from_display
    [ from_name.to_s.strip.presence, from_email.to_s.strip.presence ].compact.join(" ").strip.presence || "Unknown sender"
  end

  def participants_text
    [ formatted_recipient_list(to_recipients_json), formatted_recipient_list(cc_recipients_json) ].reject(&:blank?).join("\n")
  end

  def search_source_text
    [
      display_subject,
      from_display,
      participants_text,
      snippet,
      body_text
    ].compact.join("\n").squish
  end

  private

  def normalize_message_fields
    self.subject = subject.to_s.strip
    self.from_name = from_name.to_s.strip.presence
    self.from_email = from_email.to_s.strip.downcase.presence
    self.snippet = snippet.to_s.squish.presence
    self.thread_key = thread_key.to_s.strip.presence
    self.internet_message_id = internet_message_id.to_s.strip.presence
    self.provider_thread_id = provider_thread_id.to_s.strip.presence
    self.body_text = body_text.to_s.presence
    self.body_html = body_html.to_s.presence
    self.to_recipients_json = normalize_recipients(to_recipients_json)
    self.cc_recipients_json = normalize_recipients(cc_recipients_json)
    self.bcc_recipients_json = normalize_recipients(bcc_recipients_json)
    self.reply_to_recipients_json = normalize_recipients(reply_to_recipients_json)
    self.attachment_metadata_json = Array(attachment_metadata_json).filter_map { |item| item.is_a?(Hash) ? item.compact : nil }
    self.headers_json = headers_json.to_h
    self.metadata_json = metadata_json.to_h
  end

  def normalize_recipients(values)
    Array(values).filter_map do |item|
      next unless item.is_a?(Hash)

      email = item["email"].to_s.strip.downcase.presence
      name = item["name"].to_s.strip.presence
      next if email.blank? && name.blank?

      {
        "name" => name,
        "email" => email
      }.compact
    end
  end

  def formatted_recipient_list(values)
    Array(values).filter_map do |recipient|
      next unless recipient.is_a?(Hash)

      [ recipient["name"].to_s.strip.presence, recipient["email"].to_s.strip.presence ].compact.join(" ").strip.presence
    end.join(", ")
  end

  def search_chunk_reindex_required?
    return true if previous_changes.key?("id")

    (previous_changes.keys & SEARCH_REINDEX_CHANGE_KEYS).any?
  end

  def enqueue_search_chunk_reindex
    Search::IndexEpistulariumMessageJob.perform_later(id)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    Rails.logger.warn("Search index queue unavailable for epistularium_message=#{id}: #{error.class}: #{error.message}")
    Search::ChunkIndexingService.index_epistularium_message!(epistularium_message: self)
  end

  def remove_search_chunks
    Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE, source_id: id)
  end
end
