module Meetings
  class ExtensionTokenService
    TOKEN_EXPIRY = 90.days

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
    end

    def issue!
      revoke!
      user.api_tokens.create!(
        name: token_name,
        expires_at: TOKEN_EXPIRY.from_now
      )
    end

    def revoke!
      active_tokens.find_each do |token|
        token.revoke!
      end
    end

    def latest_active_token
      active_tokens.order(created_at: :desc).first
    end

    def token_name
      "Google Meet transcript extension (#{workspace.slug})"
    end

    private

    attr_reader :user, :workspace

    def active_tokens
      user.api_tokens.active.where(name: token_name)
    end
  end
end
