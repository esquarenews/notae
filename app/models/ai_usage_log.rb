class AiUsageLog < ApplicationRecord
  OP_SEMANTIC_QUERY = "semantic_query_embedding"
  OP_SEMANTIC_BACKFILL = "semantic_chunk_backfill"
  OP_SEARCH_ANSWER = "search_answer_generation"
  OP_ASSISTANT_QUERY = "assistant_query_generation"
  OP_ASSISTANT_WRITE = "assistant_write_generation"
  OP_KNOWLEDGE_SUGGESTION = "knowledge_suggestion_generation"
  OP_MEETING_TRANSCRIPTION = "meeting_transcription"
  OP_MEETING_SUMMARY = "meeting_summary_generation"
  OPERATIONS = [
    OP_SEMANTIC_QUERY,
    OP_SEMANTIC_BACKFILL,
    OP_SEARCH_ANSWER,
    OP_ASSISTANT_QUERY,
    OP_ASSISTANT_WRITE,
    OP_KNOWLEDGE_SUGGESTION,
    OP_MEETING_TRANSCRIPTION,
    OP_MEETING_SUMMARY
  ].freeze
  OPERATION_LABELS = {
    OP_SEMANTIC_QUERY => "Semantic query embedding",
    OP_SEMANTIC_BACKFILL => "Semantic chunk backfill",
    OP_SEARCH_ANSWER => "Search answer generation",
    OP_ASSISTANT_QUERY => "Assistant query generation",
    OP_ASSISTANT_WRITE => "Assistant write generation",
    OP_KNOWLEDGE_SUGGESTION => "Knowledge suggestion generation",
    OP_MEETING_TRANSCRIPTION => "Meeting diarization",
    OP_MEETING_SUMMARY => "Meeting summary generation"
  }.freeze

  belongs_to :user
  belongs_to :workspace

  validates :operation, inclusion: { in: OPERATIONS }
  validates :model, presence: true
  validates :prompt_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :completion_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :estimated_cost_usd, numericality: { greater_than_or_equal_to: 0 }

  scope :for_user_and_workspace, ->(user:, workspace:) { where(user_id: user.id, workspace_id: workspace.id) }
  scope :for_day, ->(day_start, day_end) { where(created_at: day_start..day_end) }

  def self.label_for(operation)
    OPERATION_LABELS[operation.to_s] || operation.to_s.humanize
  end
end
