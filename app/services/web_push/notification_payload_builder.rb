module WebPush
  class NotificationPayloadBuilder
    include Rails.application.routes.url_helpers

    def initialize(notification:)
      @notification = notification
    end

    def call
      {
        notification_id: notification.id,
        title: title,
        body: body,
        url: destination_url,
        tag: "notae-#{notification.notification_type}-#{notification.id}",
        icon: "/icon-192-v2.png",
        badge: "/icon-192-v2.png"
      }
    end

    private

    attr_reader :notification

    def title
      case notification.notification_type
      when Notification::TYPE_CALENDAR_REMINDER
        "Reminder from #{workspace_name}"
      when Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED
        "Agent draft awaiting approval"
      when Notification::TYPE_AGENT_ACTION_RESUBMITTED
        "Agent draft resubmitted"
      when Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED
        "Changes requested on a draft"
      when Notification::TYPE_AGENT_ACTION_APPROVED
        "Draft approved"
      when Notification::TYPE_AGENT_ACTION_REJECTED
        "Draft rejected"
      when Notification::TYPE_WORKFLOW_FAILED
        "Workflow failed"
      when Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
        knowledge_suggestion_title
      else
        "#{actor_name} mentioned you"
      end
    end

    def body
      case notification.notification_type
      when Notification::TYPE_CALENDAR_REMINDER
        event = notification.notifiable if notification.notifiable.is_a?(KalendariumEvent)
        return "Open Notifications in Notae." if event.blank?

        "#{event.title} · #{event.starts_at_utc.in_time_zone(time_zone).strftime("%b %-d %H:%M")}"
      when Notification::TYPE_WORKFLOW_FAILED
        workflow_run = notification.notifiable if notification.notifiable.is_a?(WorkflowRun)
        return "Open Notifications in Notae." if workflow_run.blank?

        [ workflow_run.workflow_kind.to_s.humanize, workflow_run.error_message.presence || "The workflow did not complete." ].join(" · ")
      when Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
        suggestion = notification.notifiable if notification.notifiable.is_a?(KnowledgeSuggestion)
        return "Open Notifications in Notae." if suggestion.blank?

        [
          suggestion.title.presence,
          comment_excerpt(suggestion.summary)
        ].compact.join(" · ")
      when Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
           Notification::TYPE_AGENT_ACTION_RESUBMITTED,
           Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED,
           Notification::TYPE_AGENT_ACTION_APPROVED,
           Notification::TYPE_AGENT_ACTION_REJECTED
        agent_action = notification.notifiable if notification.notifiable.is_a?(AgentAction)
        base = if agent_action.present?
          [
            agent_action.title,
            agent_action.target_system.to_s.titleize,
            agent_action.draft_type.to_s.humanize
          ].compact.join(" · ")
        else
          notification.metadata["title"].to_s
        end
        [ base.presence, notification.metadata["comment"].to_s.presence ].compact.join(" — ")
      else
        comment = notification.notifiable if notification.notifiable.is_a?(Comment)
        comment_excerpt(comment&.body.to_s)
      end.presence || "Open Notifications in Notae."
    end

    def destination_url
      case notification.notification_type
      when Notification::TYPE_CALENDAR_REMINDER
        event = notification.notifiable if notification.notifiable.is_a?(KalendariumEvent)
        return fallback_url if event.blank?

        kalendarium_path(
          workspace_slug: notification.workspace.slug,
          view: "day",
          date: event.starts_at_utc.to_date,
          anchor: "kalendarium_event_#{event.id}"
        )
      when Notification::TYPE_WORKFLOW_FAILED
        workflow_run = notification.notifiable if notification.notifiable.is_a?(WorkflowRun)
        return fallback_url if workflow_run.blank?

        workflow_run_path(workspace_slug: notification.workspace.slug, id: workflow_run.id)
      when Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
        suggestion = notification.notifiable if notification.notifiable.is_a?(KnowledgeSuggestion)
        return fallback_url if suggestion.blank?

        workspace_path(
          notification.workspace.slug,
          show_home: 1,
          anchor: "knowledge-suggestion-#{suggestion.id}"
        )
      when Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
           Notification::TYPE_AGENT_ACTION_RESUBMITTED,
           Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED,
           Notification::TYPE_AGENT_ACTION_APPROVED,
           Notification::TYPE_AGENT_ACTION_REJECTED
        agent_action = notification.notifiable if notification.notifiable.is_a?(AgentAction)
        return fallback_url if agent_action.blank?

        agent_action_path(workspace_slug: notification.workspace.slug, id: agent_action.id)
      else
        comment_destination_url || fallback_url
      end
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

    def comment_excerpt(raw_text)
      plain = ActionController::Base.helpers.strip_tags(raw_text.to_s).squish
      return nil if plain.blank?

      plain.truncate(140)
    end

    def actor_name
      notification.actor&.email.presence || workspace_name
    end

    def knowledge_suggestion_title
      suggestion = notification.notifiable
      return "New AI suggestion" unless suggestion.is_a?(KnowledgeSuggestion)

      suggestion.kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY ? "Daily workspace brief ready" : "New AI suggestion"
    end

    def workspace_name
      notification.workspace&.name.presence || "Notae"
    end

    def time_zone
      ActiveSupport::TimeZone[notification.recipient&.time_zone] || Time.zone || ActiveSupport::TimeZone["UTC"]
    end
  end
end
