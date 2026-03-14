module Workflows
  class NotificationService
    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def notify_failed!
      Membership.where(workspace_id: workflow_run.workspace_id, role: %w[admin owner]).includes(:user).find_each do |membership|
        Notification.create!(
          workspace: workflow_run.workspace,
          actor: workflow_run.user,
          recipient: membership.user,
          notifiable: workflow_run,
          notification_type: Notification::TYPE_WORKFLOW_FAILED,
          metadata: {
            "workflow_run_id" => workflow_run.id,
            "workflow_kind" => workflow_run.workflow_kind,
            "status" => workflow_run.status,
            "error_message" => workflow_run.error_message
          }
        )
      end
    end

    private

    attr_reader :workflow_run
  end
end
