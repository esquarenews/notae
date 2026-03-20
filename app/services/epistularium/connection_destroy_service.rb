module Epistularium
  class ConnectionDestroyService
    def initialize(account:)
      @account = account
    end

    def call
      message_ids = account.epistularium_messages.select(:id)

      EpistulariumAccount.transaction do
        SearchChunk.where(source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE, source_id: message_ids).delete_all
        SearchChunk.where(epistularium_message_id: message_ids).delete_all if SearchChunk.reference_column_available?(:epistularium_message_id)
        account.epistularium_messages.delete_all
        account.destroy!
      end
    end

    private

    attr_reader :account
  end
end
