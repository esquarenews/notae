module Search
  class BackfillChunkEmbeddingsJob < ApplicationJob
    queue_as :default

    def perform(user_id, workspace_id, chunk_ids)
      user = User.find_by(id: user_id)
      workspace = Workspace.find_by(id: workspace_id)
      return if user.blank? || workspace.blank?
      return unless user.openai_api_key_configured?
      return unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)

      chunks = SearchChunk.where(id: chunk_ids, workspace_id: workspace.id).order(:chunk_index).to_a
      return if chunks.empty?

      response = Openai::EmbeddingsClient.embed_many_with_usage(
        texts: chunks.map(&:text),
        api_key: user.openai_api_key,
        model: SearchChunk::EMBEDDING_MODEL
      )

      chunks.zip(response[:embeddings]).each do |chunk, embedding|
        next if embedding.blank?

        chunk.update_columns(
          embedding: embedding,
          embedding_model: SearchChunk::EMBEDDING_MODEL,
          updated_at: Time.current
        )
      end

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_SEMANTIC_BACKFILL,
        model: SearchChunk::EMBEDDING_MODEL,
        usage: response[:usage],
        metadata: { chunk_count: chunks.length, job: "backfill_chunk_embeddings" }
      )
    rescue Openai::EmbeddingsClient::Error => e
      Rails.logger.warn("Chunk embedding backfill failed for workspace=#{workspace_id}: #{e.message}")
    end
  end
end
