module Notifications
  class DestinationResolver
    include Rails.application.routes.url_helpers

    def initialize(notification:)
      @notification = notification
    end

    def call
      case notification.notification_type
      when Notification::TYPE_CALENDAR_REMINDER
        calendar_destination_url
      when Notification::TYPE_WORKFLOW_FAILED
        workflow_destination_url
      when Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
        knowledge_suggestion_destination_url
      when Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
           Notification::TYPE_AGENT_ACTION_RESUBMITTED,
           Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED,
           Notification::TYPE_AGENT_ACTION_APPROVED,
           Notification::TYPE_AGENT_ACTION_REJECTED
        agent_action_destination_url
      else
        comment_destination_url
      end || fallback_url
    end

    private

    attr_reader :notification

    def calendar_destination_url
      event = notification.notifiable if notification.notifiable.is_a?(KalendariumEvent)
      return if event.blank?

      kalendarium_path(
        workspace_slug: notification.workspace.slug,
        view: "day",
        date: event.starts_at_utc.to_date,
        anchor: "kalendarium_event_#{event.id}"
      )
    end

    def workflow_destination_url
      workflow_run = notification.notifiable if notification.notifiable.is_a?(WorkflowRun)
      return if workflow_run.blank?

      workflow_run_path(workspace_slug: notification.workspace.slug, id: workflow_run.id)
    end

    def knowledge_suggestion_destination_url
      suggestion = notification.notifiable if notification.notifiable.is_a?(KnowledgeSuggestion)
      return if suggestion.blank?

      workspace_path(
        notification.workspace.slug,
        show_home: 1,
        anchor: "knowledge-suggestion-#{suggestion.id}"
      )
    end

    def agent_action_destination_url
      agent_action = notification.notifiable if notification.notifiable.is_a?(AgentAction)
      return if agent_action.blank?

      agent_action_path(workspace_slug: notification.workspace.slug, id: agent_action.id)
    end

    def comment_destination_url
      comment = notification.notifiable
      return unless comment.is_a?(Comment)

      commentable = comment.commentable
      case commentable
      when Page
        page_path(workspace_slug: notification.workspace.slug, id: commentable.id)
      when Block
        page_path(workspace_slug: notification.workspace.slug, id: commentable.page_id, anchor: "block_#{commentable.id}")
      when Database
        database_path(workspace_slug: notification.workspace.slug, id: commentable.id, anchor: "database-comments-menu")
      end
    end

    def fallback_url
      workspace_notifications_path(workspace_slug: notification.workspace.slug)
    end
  end
end
