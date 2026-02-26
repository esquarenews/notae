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
    delivery_options = smtp_delivery_options
    mail_attributes[:delivery_method_options] = delivery_options if delivery_options.present?

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
    return workspace_url(workspace_slug: @workspace.slug) if @page.blank?

    page_url(workspace_slug: @workspace.slug, id: @page.id, anchor: "page-comments-menu")
  end
end
