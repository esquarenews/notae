module Api
  module V1
    module Serializers
      class AgentActionSerializer
        def self.render_collection(agent_actions)
          agent_actions.map { |agent_action| render(agent_action) }
        end

        def self.render(agent_action, include_history: false)
          payload = {
            id: agent_action.id,
            workspace_id: agent_action.workspace_id,
            user_id: agent_action.user_id,
            approved_by_id: agent_action.approved_by_id,
            rejected_by_id: agent_action.rejected_by_id,
            title: agent_action.title,
            proposed_by: agent_action.proposed_by,
            target_system: agent_action.target_system,
            draft_type: agent_action.draft_type,
            status: agent_action.status,
            approval_required: agent_action.approval_required,
            dry_run: agent_action.dry_run,
            payload_json: agent_action.payload_json,
            metadata_json: agent_action.metadata_json,
            result_json: agent_action.result_json,
            policy_evaluation_json: agent_action.policy_evaluation_json,
            created_at: agent_action.created_at&.iso8601(6),
            updated_at: agent_action.updated_at&.iso8601(6)
          }

          payload[:review_history] = serialize_history(agent_action.review_history) if include_history
          payload
        end

        def self.serialize_history(events)
          Array(events).map do |event|
            {
              id: event.id,
              actor_id: event.actor_id,
              event_type: event.event_type,
              comment: event.comment,
              details_json: event.details_json,
              sequence_number: event.sequence_number,
              created_at: event.created_at&.iso8601(6)
            }
          end
        end
      end
    end
  end
end
