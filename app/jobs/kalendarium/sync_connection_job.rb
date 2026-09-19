module Kalendarium
  class SyncConnectionJob < ApplicationJob
    queue_as :default

    AUTH_FAILURE_AUTO_DISABLE_MESSAGE = "Auto-disabled after authentication failure. Update credentials and re-enable connection.".freeze
    LOCK_TTL = 10.minutes

    def perform(connection_id)
      lock_acquired = false
      connection = KalendariumConnection.find_by(id: connection_id)
      return if connection.blank?
      lock_acquired = acquire_sync_lock(connection.id)
      return unless lock_acquired

      Kalendarium::ConnectionSyncService.new(connection: connection).call
      Search::QueueKnowledgeSuggestionRefreshJob.perform_later(connection.workspace_id)
    rescue StandardError => error
      raise unless permanent_auth_failure?(error)

      connection.update!(
        enabled: false,
        status: "sync_error",
        last_error: "#{error.message} #{AUTH_FAILURE_AUTO_DISABLE_MESSAGE}"
      )
      Rails.logger.warn("Kalendarium sync auto-disabled connection=#{connection.id} provider=#{connection.provider}: #{error.class}: #{error.message}")
    ensure
      release_sync_lock(connection_id) if lock_acquired
    end

    private

    def permanent_auth_failure?(error)
      message = error.message.to_s.downcase
      return false if message.blank?

      message.include?("caldav authentication failed") ||
        message.include?("app-specific password") ||
        message.match?(/google token refresh failed \((?:400|401)\)/) ||
        message.include?("token has been expired or revoked") ||
        message.include?("invalid_grant") ||
        message.include?("oauth client was not found") ||
        message.include?("invalid_client")
    end

    def acquire_sync_lock(connection_id)
      Rails.cache.write(sync_lock_key(connection_id), true, unless_exist: true, expires_in: LOCK_TTL)
    rescue NotImplementedError
      return false if Rails.cache.read(sync_lock_key(connection_id)).present?

      Rails.cache.write(sync_lock_key(connection_id), true, expires_in: LOCK_TTL)
      true
    end

    def release_sync_lock(connection_id)
      Rails.cache.delete(sync_lock_key(connection_id))
    rescue StandardError
      nil
    end

    def sync_lock_key(connection_id)
      "kalendarium:sync_connection:#{connection_id}"
    end
  end
end
