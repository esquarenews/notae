module Api
  module V1
    class BaseController < ActionController::API
      include Pundit::Authorization
      class_attribute :required_api_token_scopes_by_action, instance_writer: false, default: {}

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
      rescue_from ActionController::ParameterMissing, with: :render_bad_request

      before_action :authenticate_api_token!
      before_action :enforce_rate_limit!
      before_action :authorize_api_token_scope!
      after_action :audit_api_token_request!, if: :audit_api_token_request?

      class << self
        def require_api_token_scopes(action_scope_map)
          normalized = action_scope_map.to_h.transform_keys(&:to_s).transform_values do |scopes|
            Array(scopes).map(&:to_s).reject(&:blank?).uniq
          end
          self.required_api_token_scopes_by_action = required_api_token_scopes_by_action.merge(normalized)
        end
      end

      private

      attr_reader :current_api_token, :current_user

      def authenticate_api_token!
        raw_token = extracted_api_token
        if raw_token.blank? || raw_token.length > 512
          render_error(code: "unauthorized", message: "Valid bearer token required", status: :unauthorized)
          return
        end

        @current_api_token = ApiToken.active.find_by(token: raw_token)

        if @current_api_token.blank?
          render_error(code: "unauthorized", message: "Valid bearer token required", status: :unauthorized)
          return
        end

        @current_user = @current_api_token.user
        @current_api_token.touch_last_used!
      end

      def enforce_rate_limit!
        return if Api::V1::RateLimiter.allowed?(token: @current_api_token)

        render_error(code: "rate_limited", message: "Rate limit exceeded", status: :too_many_requests)
      end

      def authorize_api_token_scope!
        @current_api_required_scopes = Array(self.class.required_api_token_scopes_by_action[action_name.to_s])
        return if @current_api_token.allows_any_scope?(@current_api_required_scopes)

        @api_token_scope_denied = true
        create_api_token_audit_event!("scope_denied", http_status: 403)
        render_error(
          code: "insufficient_scope",
          message: "API token does not allow this operation",
          status: :forbidden,
          details: { required_scopes: @current_api_required_scopes }
        )
      end

      def extracted_api_token
        bearer_value = request.authorization.to_s
        return bearer_value.delete_prefix("Bearer ").strip if bearer_value.start_with?("Bearer ")

        request.headers["X-API-Token"].to_s.strip
      end

      def set_workspace!
        @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
      end

      def workspace
        @workspace
      end

      def audit_api_token_request?
        return false if @current_api_token.blank?

        !@api_token_scope_denied && !request.get? && !request.head?
      end

      def audit_api_token_request!
        create_api_token_audit_event!("allowed")
      rescue StandardError => error
        Rails.logger.warn("API token audit logging failed: #{error.class}: #{error.message}")
      end

      def create_api_token_audit_event!(event_type, http_status: response.status)
        ApiTokenAuditEvent.create!(
          api_token: @current_api_token,
          user: @current_user,
          workspace: workspace_for_api_audit,
          event_type: event_type,
          request_method: request.request_method,
          path: request.fullpath,
          controller_name: self.class.name,
          action_name: action_name,
          http_status: http_status,
          required_scopes_json: @current_api_required_scopes || [],
          metadata_json: {
            token_name: @current_api_token.name,
            token_scopes: @current_api_token.scopes
          }
        )
      end

      def workspace_for_api_audit
        return workspace if defined?(@workspace) && @workspace.present?
        return nil if params[:workspace_slug].blank?

        @current_user.workspaces.find_by(slug: params[:workspace_slug])
      end

      def render_validation_errors(record)
        render_error(
          code: "validation_failed",
          message: record.errors.full_messages.to_sentence,
          details: record.errors.to_hash(true),
          status: :unprocessable_entity
        )
      end

      def render_error(code:, message:, status:, details: {})
        payload = { error: { code: code, message: message } }
        payload[:error][:details] = details if details.present?
        render json: payload, status: status
      end

      def render_not_found
        render_error(code: "not_found", message: "Resource not found", status: :not_found)
      end

      def render_forbidden
        render_error(code: "forbidden", message: "Not authorized", status: :forbidden)
      end

      def render_bad_request(error)
        render_error(code: "bad_request", message: error.message, status: :bad_request)
      end
    end
  end
end
