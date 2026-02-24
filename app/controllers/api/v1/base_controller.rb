module Api
  module V1
    class BaseController < ActionController::API
      include Pundit::Authorization

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
      rescue_from ActionController::ParameterMissing, with: :render_bad_request

      before_action :authenticate_api_token!
      before_action :enforce_rate_limit!

      private

      attr_reader :current_api_token, :current_user

      def authenticate_api_token!
        raw_token = extracted_api_token
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
