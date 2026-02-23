module Comments
  class ProcessMentionsService
    MENTION_PATTERN = /@([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})/

    def self.call(comment:)
      new(comment:).call
    end

    def initialize(comment:)
      @comment = comment
    end

    def call
      mention_emails.each do |email|
        user = comment.workspace.users.find_by("LOWER(email) = ?", email.downcase)
        next unless user
        next if user.id == comment.author_id

        Notification.find_or_create_by!(
          workspace_id: comment.workspace_id,
          recipient_id: user.id,
          actor_id: comment.author_id,
          notification_type: "mention",
          notifiable: comment
        ) do |notification|
          notification.metadata = {
            mention: email,
            comment_id: comment.id,
            commentable_type: comment.commentable_type,
            commentable_id: comment.commentable_id
          }
        end
      end
    end

    private

    attr_reader :comment

    def mention_emails
      comment.body.to_s.scan(MENTION_PATTERN).flatten.uniq
    end
  end
end
