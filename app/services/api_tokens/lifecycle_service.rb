module ApiTokens
  class LifecycleService
    def initialize(user:, workspace: nil)
      @user = user
      @workspace = workspace
    end

    def issue!(name:, scopes_json:, expires_at:, metadata: {})
      token = @user.api_tokens.create!(
        name: name,
        scopes_json: scopes_json,
        expires_at: normalize_expiry(expires_at)
      )

      log_event!(token:, event_type: "issued", metadata:)
      token
    end

    def revoke!(token, metadata: {})
      return token if token.revoked?

      token.revoke!
      log_event!(token:, event_type: "revoked", metadata:)
      token
    end

    def rotate!(token, metadata: {})
      replacement = nil

      ActiveRecord::Base.transaction do
        replacement = issue!(
          name: token.name,
          scopes_json: token.scopes,
          expires_at: rotation_expiry_for(token),
          metadata: metadata.merge(rotated_from_api_token_id: token.id)
        )

        revoke!(
          token,
          metadata: metadata.merge(rotated_to_api_token_id: replacement.id)
        )
      end

      replacement
    end

    private

    def normalize_expiry(value)
      return nil if value.blank?
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

      Time.zone.parse(value.to_s)
    end

    def rotation_expiry_for(token)
      return nil if token.expires_at.blank?
      return token.expires_at if token.expires_at.future?

      nil
    end

    def log_event!(token:, event_type:, metadata:)
      ApiTokenAuditEvent.create!(
        api_token: token,
        user: @user,
        workspace: @workspace,
        event_type: event_type,
        metadata_json: metadata.compact
      )
    end
  end
end
