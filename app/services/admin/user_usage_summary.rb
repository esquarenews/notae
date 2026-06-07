module Admin
  class UserUsageSummary
    STORAGE_RECORD_SCOPES = [
      [ Page, :workspace_id ],
      [ Database, :workspace_id ],
      [ Block, :workspace_id ],
      [ WorkspaceCoverAsset, :workspace_id ],
      [ MeetingSession, :workspace_id ],
      [ PageExport, :workspace_id ],
      [ WorkspaceExport, :workspace_id ],
      [ WorkspaceEmoji, :workspace_id ]
    ].freeze

    def initialize(users:, month_range: Time.current.beginning_of_month..Time.current)
      @users = Array(users)
      @month_range = month_range
    end

    def call
      return {} if users.empty?

      users.index_with do |user|
        workspace_ids = workspace_ids_by_user.fetch(user.id, [])
        total_ai_usage = total_ai_usage_by_user.fetch(user.id, default_ai_usage)
        monthly_ai_usage = monthly_ai_usage_by_user.fetch(user.id, default_ai_usage)
        document_count = workspace_ids.sum { |workspace_id| document_counts_by_workspace.fetch(workspace_id, 0) }
        storage_bytes = workspace_ids.sum { |workspace_id| storage_bytes_by_workspace.fetch(workspace_id, 0) } +
          avatar_storage_bytes_by_user.fetch(user.id, 0)

        {
          workspace_count: workspace_ids.size,
          document_count: document_count,
          total_ai_requests: total_ai_usage.fetch(:requests),
          monthly_ai_requests: monthly_ai_usage.fetch(:requests),
          total_spend_usd: total_ai_usage.fetch(:cost_usd),
          monthly_spend_usd: monthly_ai_usage.fetch(:cost_usd),
          storage_bytes: storage_bytes,
          first_signed_at: user.created_at,
          over_workspace_limit: user.workspace_limit.present? && workspace_ids.size > user.workspace_limit
        }
      end
    end

    private

    attr_reader :users, :month_range

    def user_ids
      @user_ids ||= users.map(&:id)
    end

    def all_workspace_ids
      @all_workspace_ids ||= workspace_ids_by_user.values.flatten.uniq
    end

    def workspace_ids_by_user
      @workspace_ids_by_user ||= Membership
        .where(user_id: user_ids)
        .group_by(&:user_id)
        .transform_values { |memberships| memberships.map(&:workspace_id).uniq }
    end

    def total_ai_usage_by_user
      @total_ai_usage_by_user ||= ai_usage_scope(AiUsageLog.where(user_id: user_ids))
    end

    def monthly_ai_usage_by_user
      @monthly_ai_usage_by_user ||= ai_usage_scope(AiUsageLog.where(user_id: user_ids, created_at: month_range))
    end

    def ai_usage_scope(scope)
      scope
        .group(:user_id)
        .pluck(:user_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"))
        .each_with_object({}) do |(user_id, request_count, cost_sum), usage|
          usage[user_id] = {
            requests: request_count.to_i,
            cost_usd: cost_sum.to_f.round(4)
          }
        end
    end

    def default_ai_usage
      { requests: 0, cost_usd: 0.0 }
    end

    def document_counts_by_workspace
      @document_counts_by_workspace ||= begin
        counts = Hash.new(0)
        [ Page, Database ].each do |model|
          model.where(workspace_id: all_workspace_ids).group(:workspace_id).count.each do |workspace_id, count|
            counts[workspace_id] += count
          end
        end
        counts
      end
    end

    def storage_bytes_by_workspace
      @storage_bytes_by_workspace ||= begin
        totals = Hash.new(0)
        STORAGE_RECORD_SCOPES.each do |model, workspace_key|
          ids_by_workspace = model.where(workspace_key => all_workspace_ids).pluck(:id, workspace_key).to_h
          next if ids_by_workspace.empty?

          attachment_bytes_for(model.name, ids_by_workspace.keys).each do |record_id, bytes|
            totals[ids_by_workspace.fetch(record_id)] += bytes.to_i
          end
        end
        totals
      end
    end

    def avatar_storage_bytes_by_user
      @avatar_storage_bytes_by_user ||= attachment_bytes_for(User.name, user_ids)
    end

    def attachment_bytes_for(record_type, record_ids)
      return {} if record_ids.blank?

      ActiveStorage::Attachment
        .joins(:blob)
        .where(record_type: record_type, record_id: record_ids)
        .group(:record_id)
        .sum("active_storage_blobs.byte_size")
    end
  end
end
