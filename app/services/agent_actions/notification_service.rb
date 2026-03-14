module AgentActions
  class NotificationService
    def initialize(agent_action:, actor:)
      @agent_action = agent_action
      @actor = actor
    end

    def notify_approval_requested!
      notify_approvers!(Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED)
    end

    def notify_resubmitted!
      notify_approvers!(Notification::TYPE_AGENT_ACTION_RESUBMITTED)
    end

    def notify_changes_requested!(comment:)
      notify_author!(Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED, comment: comment)
    end

    def notify_approved!(comment:)
      notify_author!(Notification::TYPE_AGENT_ACTION_APPROVED, comment: comment)
    end

    def notify_rejected!(comment:)
      notify_author!(Notification::TYPE_AGENT_ACTION_REJECTED, comment: comment)
    end

    private

    attr_reader :agent_action, :actor

    def notify_author!(notification_type, comment:)
      recipient = agent_action.user
      return if recipient.blank?
      return if actor.present? && recipient.id == actor.id

      create_notification!(recipient: recipient, notification_type: notification_type, comment: comment)
    end

    def notify_approvers!(notification_type)
      approver_roles = effective_policy.approver_roles
      memberships_scope = Membership.where(workspace_id: agent_action.workspace_id, role: approver_roles)
      memberships_scope.includes(:user).find_each do |membership|
        recipient = membership.user
        next if recipient.blank?
        next if actor.present? && recipient.id == actor.id

        create_notification!(recipient: recipient, notification_type: notification_type)
      end
    end

    def create_notification!(recipient:, notification_type:, comment: nil)
      Notification.create!(
        workspace: agent_action.workspace,
        actor: actor || agent_action.user,
        recipient: recipient,
        notifiable: agent_action,
        notification_type: notification_type,
        metadata: {
          "agent_action_id" => agent_action.id,
          "title" => agent_action.title,
          "draft_type" => agent_action.draft_type,
          "target_system" => agent_action.target_system,
          "status" => agent_action.status,
          "comment" => comment,
          "workspace_slug" => agent_action.workspace.slug
        }
      )
    end

    def effective_policy
      @effective_policy ||= agent_action.workspace.agent_policy || agent_action.workspace.build_agent_policy
    end
  end
end
