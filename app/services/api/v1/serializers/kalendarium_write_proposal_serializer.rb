module Api
  module V1
    module Serializers
      class KalendariumWriteProposalSerializer
        def self.render(proposal)
          {
            id: proposal.id,
            workspace_id: proposal.workspace_id,
            user_id: proposal.user_id,
            event_id: proposal.kalendarium_event_id,
            proposed_by: proposal.proposed_by,
            operation: proposal.operation,
            status: proposal.status,
            payload_json: proposal.payload_json,
            error_message: proposal.error_message,
            expires_at: proposal.expires_at&.iso8601(6),
            applied_at: proposal.applied_at&.iso8601(6),
            rejected_at: proposal.rejected_at&.iso8601(6),
            created_at: proposal.created_at&.iso8601(6),
            updated_at: proposal.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
