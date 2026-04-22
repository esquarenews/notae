module TenantLimits
  class Snapshot
    def initialize(workspace:)
      @workspace = workspace
    end

    def call
      subscription = workspace.subscription_record
      limits = subscription.effective_limits
      current_usage = usage

      {
        plan_key: subscription.plan_key,
        plan_name: Billing::PlanCatalog.name_for(subscription.plan_key),
        status: subscription.status,
        limits: limits,
        usage: current_usage,
        exceeded: exceeded(limits, current_usage)
      }
    end

    private

    attr_reader :workspace

    def usage
      {
        members: workspace.memberships.count,
        storage_mb: storage_megabytes,
        ai_requests_this_month: workspace.ai_usage_logs.where(created_at: Time.current.beginning_of_month..Time.current).count,
        integrations: workspace.kalendarium_connections.count + workspace.epistularium_accounts.count,
        exports_this_month: workspace.workspace_exports.where(created_at: Time.current.beginning_of_month..Time.current).count
      }
    end

    def exceeded(limits, current_usage)
      {
        members: current_usage.fetch(:members) > limits.fetch(:members),
        storage_mb: current_usage.fetch(:storage_mb) > limits.fetch(:storage_mb),
        ai_requests_per_month: current_usage.fetch(:ai_requests_this_month) > limits.fetch(:ai_requests_per_month),
        integrations: current_usage.fetch(:integrations) > limits.fetch(:integrations),
        exports_per_month: current_usage.fetch(:exports_this_month) > limits.fetch(:exports_per_month)
      }
    end

    def storage_megabytes
      bytes = workspace_storage_scopes.sum do |record_type, ids|
        next 0 if ids.empty?

        ActiveStorage::Attachment
          .joins(:blob)
          .where(record_type: record_type, record_id: ids)
          .sum("active_storage_blobs.byte_size")
      end

      (bytes.to_f / 1.megabyte).round(2)
    end

    def workspace_storage_scopes
      {
        "Page" => workspace.pages.pluck(:id),
        "Database" => workspace.databases.pluck(:id),
        "WorkspaceCoverAsset" => workspace.cover_assets.pluck(:id),
        "MeetingSession" => workspace.meeting_sessions.pluck(:id)
      }
    end
  end
end
