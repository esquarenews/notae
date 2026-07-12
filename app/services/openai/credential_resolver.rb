module Openai
  class CredentialResolver
    class << self
      def resolve(user:)
        new(user: user).resolve
      end

      alias_method :call, :resolve

      def configured?(user:)
        resolve(user: user).present?
      end
    end

    def initialize(user:)
      @user = user
    end

    def resolve
      user_api_key.presence || server_api_key.presence
    end

    private

    attr_reader :user

    def user_api_key
      return unless user.respond_to?(:openai_api_key)

      user.openai_api_key.to_s.strip
    rescue ActiveRecord::Encryption::Errors::Base
      nil
    end

    def server_api_key
      ENV["OPENAI_API_KEY"].to_s.strip
    end
  end
end
