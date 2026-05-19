class NotificationMailer < ApplicationMailer
  def mention_notification
    @notification = params[:notification]
    @recipient = @notification.recipient
    @actor = @notification.actor
    @workspace = @notification.workspace
    @comment = @notification.notifiable
    @page = resolve_page(@comment)
    @comment_url = resolve_comment_url

    mail_attributes = {
      to: @recipient.email,
      subject: "#{@actor.email} mentioned you in #{@workspace.name}",
      from: mail_from_value
    }

    mail(mail_attributes)
  end

  def calendar_reminder_notification
    @notification = params[:notification]
    @recipient = @notification.recipient
    @actor = @notification.actor
    @workspace = @notification.workspace
    @event = @notification.notifiable.is_a?(KalendariumEvent) ? @notification.notifiable : nil
    @reminder_url =
      if @event.present?
        kalendarium_url(workspace_slug: @workspace.slug, view: "day", date: @event.starts_at_utc.to_date, anchor: "kalendarium_event_#{@event.id}")
      else
        workspace_url(workspace_slug: @workspace.slug)
      end

    mail_attributes = {
      to: @recipient.email,
      subject: "Reminder: #{@event&.title || 'Kalendarium event'}",
      from: mail_from_value
    }

    mail(mail_attributes)
  end

  private

  def resolve_page(comment)
    commentable = comment.respond_to?(:commentable) ? comment.commentable : nil

    case commentable
    when Page
      commentable
    when Block
      commentable.page
    else
      nil
    end
  end

  def resolve_comment_url
    if @comment.commentable.is_a?(Database)
      return database_url(workspace_slug: @workspace.slug, id: @comment.commentable_id, anchor: "database-comments-menu")
    end
    return workspace_url(workspace_slug: @workspace.slug) if @page.blank?

    page_url(workspace_slug: @workspace.slug, id: @page.id, anchor: "page-comments-menu")
  end
end
