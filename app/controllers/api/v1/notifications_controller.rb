module Api
  module V1
    class NotificationsController < BaseController
      require_api_token_scopes codex_completion: ApiToken::SCOPE_NOTIFICATIONS_WRITE

      before_action :set_workspace!

      def codex_completion
        authorize workspace, :show?

        notification = Notification.create!(
          workspace: workspace,
          actor: current_user,
          recipient: current_user,
          notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
          metadata: codex_completion_metadata
        )

        render json: {
          data: {
            notification: {
              id: notification.id,
              workspace_id: notification.workspace_id,
              recipient_id: notification.recipient_id,
              notification_type: notification.notification_type,
              title: notification.metadata["title"],
              body: notification.metadata["body"],
              path: notification.metadata["path"],
              created_at: notification.created_at.iso8601(6)
            },
            url: pwa_notification_launch_path(id: notification.id)
          }
        }, status: :created
      end

      private

      def codex_completion_params
        params.require(:notification).permit(:title, :body, :path)
      end

      def codex_completion_metadata
        title = codex_completion_params[:title].to_s.strip
        body = codex_completion_params[:body].to_s.strip
        path = codex_completion_params[:path].to_s.strip

        {
          "title" => Notification.normalize_codex_completion_title(title),
          "body" => body.presence,
          "path" => normalize_internal_path(path)
        }.compact
      end

      def normalize_internal_path(path)
        Notifications::InternalPathSanitizer.call(path, fallback: workspace_path(workspace.slug))
      end
    end
  end
end
