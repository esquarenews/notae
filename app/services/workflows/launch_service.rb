module Workflows
  class LaunchService
    class Error < StandardError; end

    EXECUTION_MODE_ASYNC = "async".freeze
    EXECUTION_MODE_INLINE = "inline".freeze
    EXECUTION_MODES = [ EXECUTION_MODE_ASYNC, EXECUTION_MODE_INLINE ].freeze

    def initialize(workspace:, actor:, workflow_kind:, input:, trigger_source: "manual", confidence_score: 1.0, execution_mode: EXECUTION_MODE_ASYNC)
      @workspace = workspace
      @actor = actor
      @workflow_kind = workflow_kind.to_s
      @input = input.to_h.stringify_keys
      @trigger_source = trigger_source.to_s
      @confidence_score = confidence_score.to_f
      @execution_mode = execution_mode.to_s
    end

    def call
      raise Error, "Unsupported workflow execution mode" unless EXECUTION_MODES.include?(execution_mode)

      decision = safety_decision
      raise Error, decision.reasons.join(", ") unless decision.allowed

      validate_target_access!

      workflow_run = WorkflowRun.new(
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
        policy_snapshot_json: decision.to_h,
        metadata_json: { "execution_mode" => execution_mode }
      )
      Pundit.authorize(actor, workflow_run, :create?)
      workflow_run.save!

      AuditEventLogger.log_workflow_run!(
        workflow_run,
        action: "workflow_run_queued",
        metadata: { input: input, trigger_source: trigger_source, execution_mode: execution_mode }
      )
      if execution_mode == EXECUTION_MODE_INLINE
        Workflows::Executor.new(workflow_run: workflow_run).call
      else
        Workflows::ExecuteRunJob.perform_later(workflow_run.id)
      end

      workflow_run.reload
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    rescue Pundit::NotAuthorizedError
      raise Error, "You are not authorized to launch this workflow"
    end

    private

    attr_reader :workspace, :actor, :workflow_kind, :input, :trigger_source, :confidence_score, :execution_mode

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
      when WorkflowRun::KIND_UPDATE_NOTA
        page = Pundit.policy_scope!(actor, Page).for_workspace(workspace).active.find_by(id: input["page_id"])
        raise Error, "Select a nota you can update" if page.blank?

        Pundit.authorize(actor, page, :update?)
      when WorkflowRun::KIND_CREATE_TASK
        database = Pundit.policy_scope!(actor, Database).for_workspace(workspace).active.find_by(id: input["database_id"])
        raise Error, "Select an internal database for automated task creation" if database.blank?
        raise Error, "Grid is locked. Unlock it before adding rows." if database.locked?

        Pundit.authorize(actor, database, :update?)
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        calendar = Pundit.policy_scope!(actor, KalendariumCalendar).for_workspace(workspace).shown_in_kalendarium.find_by(id: input["kalendarium_calendar_id"])
        raise Error, "Select a writable calendar for automation" if calendar.blank? || !calendar.user_writable?

        Pundit.authorize(actor, calendar, :update?)
      end
    end
  end
end
