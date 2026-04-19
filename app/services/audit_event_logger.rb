class AuditEventLogger
  class << self
    def log!(workspace:, actor:, action:, metadata: {}, auditable: nil)
      AuditEvent.create!(
        workspace: workspace,
        actor: actor,
        action: action,
        metadata: metadata,
        auditable: auditable
      )
    end

    def log_agent_action_event!(agent_action_event)
      agent_action = agent_action_event.agent_action
      actor = agent_action_event.actor || agent_action.user
      return if actor.blank?

      log!(
        workspace: agent_action_event.workspace,
        actor: actor,
        action: "agent_action_#{agent_action_event.event_type}",
        metadata: {
          kind: "agent_action_event",
          agent_action_id: agent_action.id,
          agent_action_event_id: agent_action_event.id,
          sequence_number: agent_action_event.sequence_number,
          target_system: agent_action.target_system,
          draft_type: agent_action.draft_type,
          status: agent_action.status,
          audit_context: agent_action.audit_context,
          comment: agent_action_event.comment,
          details: agent_action_event.details_json.to_h,
          entry_hash: agent_action_event.entry_hash,
          previous_entry_hash: agent_action_event.previous_entry_hash
        },
        auditable: agent_action
      )
    end

    def log_workflow_run!(workflow_run, action:, metadata: {})
      log!(
        workspace: workflow_run.workspace,
        actor: workflow_run.user,
        action: action,
        metadata: {
          kind: "workflow_run",
          workflow_run_id: workflow_run.id,
          workflow_kind: workflow_run.workflow_kind,
          status: workflow_run.status,
          attempts_count: workflow_run.attempts_count,
          error_message: workflow_run.error_message
        }.merge(metadata),
        auditable: workflow_run
      )
    end
  end
end
