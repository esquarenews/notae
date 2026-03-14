module Workflows
  class LaunchService
    class Error < StandardError; end

    def initialize(workspace:, actor:, workflow_kind:, input:, trigger_source: "manual", confidence_score: 1.0)
      @workspace = workspace
      @actor = actor
      @workflow_kind = workflow_kind.to_s
      @input = input.to_h.stringify_keys
      @trigger_source = trigger_source.to_s
      @confidence_score = confidence_score.to_f
    end

    def call
      decision = safety_decision
      raise Error, decision.reasons.join(", ") unless decision.allowed

      validate_target_access!

      workflow_run = WorkflowRun.create!(
        workspace: workspace,
        user: actor,
        workflow_kind: workflow_kind,
        status: WorkflowRun::STATUS_QUEUED,
        trigger_source: trigger_source.presence || "manual",
        attempts_count: 0,
        max_attempts: decision.retry_limit,
        confidence_score: confidence_score,
        queued_at: Time.current,
        input_json: input,
        plan_json: planner.call,
        policy_snapshot_json: decision.to_h
      )

      AuditEventLogger.log_workflow_run!(
        workflow_run,
        action: "workflow_run_queued",
        metadata: { input: input, trigger_source: trigger_source }
      )
      Workflows::ExecuteRunJob.perform_later(workflow_run.id)
      workflow_run
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :workspace, :actor, :workflow_kind, :input, :trigger_source, :confidence_score

    def planner
      @planner ||= Workflows::Planner.new(workflow_kind: workflow_kind, input: input)
    end

    def safety_decision
      @safety_decision ||= Workflows::SafetyEnvelope.new(
        workspace: workspace,
        actor: actor,
        workflow_kind: workflow_kind,
        confidence_score: confidence_score
      ).evaluate
    end

    def validate_target_access!
      case workflow_kind
      when WorkflowRun::KIND_CREATE_TASK
        database = Pundit.policy_scope!(actor, Database).for_workspace(workspace).active.find_by(id: input["database_id"])
        raise Error, "Select an internal database for automated task creation" if database.blank?
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        calendar = Pundit.policy_scope!(actor, KalendariumCalendar).for_workspace(workspace).find_by(id: input["kalendarium_calendar_id"])
        raise Error, "Select a local or project calendar for automation" if calendar.blank?
        raise Error, "Provider calendars are not allowed for automation" if calendar.source_kind == "provider"
      end
    end
  end
end
