module Meetings
  class ExtensionTokenService
    class UnavailableError < StandardError; end

    TOKEN_EXPIRY = 90.days
    TOKEN_REFERENCE_EXPIRY = 5.minutes
    TOKEN_REFERENCE_PURPOSE = "meeting_extension_token_reveal".freeze

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
    end

    def issue!
      raise UnavailableError, "API token storage is unavailable." unless storage_available?

      revoke!
      user.api_tokens.create!(
        name: token_name,
        expires_at: TOKEN_EXPIRY.from_now
      )
    end

    def revoke!
      return unless storage_available?

      active_tokens.find_each do |token|
        token.revoke!
      end
    end

    def latest_active_token
      return nil unless storage_available?

      active_tokens.order(created_at: :desc).first
    end

    def issue_reference(token)
      token.signed_id(purpose: TOKEN_REFERENCE_PURPOSE, expires_in: TOKEN_REFERENCE_EXPIRY)
    end

    def find_active_token_by_reference(reference)
      return nil unless storage_available?

      token = ApiToken.find_signed(reference, purpose: TOKEN_REFERENCE_PURPOSE)
      return nil if token.blank?
      return nil unless token.user_id == user.id
      return nil unless token.name == token_name
      return nil unless token.active?

      token
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def storage_available?
      ActiveRecord::Base.connection.data_source_exists?("api_tokens")
    rescue ActiveRecord::StatementInvalid => error
      raise unless optional_schema_error?(error)

      false
    end

    def token_name
      "Google Meet transcript extension (#{workspace.slug})"
    end

    private

    attr_reader :user, :workspace

    def active_tokens
      user.api_tokens.active.where(name: token_name)
    end

    def optional_schema_error?(error)
      optional_schema_error_message?(error.message) || optional_schema_error_message?(error.cause&.message)
    end

    def optional_schema_error_message?(message)
      text = message.to_s
      text.include?("PG::UndefinedTable") ||
        text.include?("PG::UndefinedColumn") ||
        text.include?("no such table") ||
        text.include?("no such column") ||
        (text.include?("relation") && text.include?("does not exist"))
    end
  end
end
