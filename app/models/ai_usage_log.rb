class AiUsageLog < ApplicationRecord
  OP_SEMANTIC_QUERY = "semantic_query_embedding"
  OP_SEMANTIC_BACKFILL = "semantic_chunk_backfill"
  OP_SEARCH_ANSWER = "search_answer_generation"
  OP_ASSISTANT_QUERY = "assistant_query_generation"
  OP_ASSISTANT_WRITE = "assistant_write_generation"
  OPERATIONS = [
    OP_SEMANTIC_QUERY,
    OP_SEMANTIC_BACKFILL,
    OP_SEARCH_ANSWER,
    OP_ASSISTANT_QUERY,
    OP_ASSISTANT_WRITE
  ].freeze

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
end
