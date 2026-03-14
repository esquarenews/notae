module Workflows
  class Executor
    RETRY_DELAY = 5.seconds

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      kill_if_disabled!
      return workflow_run if workflow_run.finished?

      workflow_run.update!(
        status: WorkflowRun::STATUS_RUNNING,
        attempts_count: workflow_run.attempts_count + 1,
        started_at: workflow_run.started_at || Time.current,
        error_message: nil
      )
      AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_started")

      result = execute_action
      workflow_run.update!(
        status: WorkflowRun::STATUS_SUCCEEDED,
        finished_at: Time.current,
        result_json: result,
        error_message: nil
      )
      AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_succeeded", metadata: result)
      workflow_run
    rescue StandardError => e
      handle_failure(e)
    end

    private

    attr_reader :workflow_run

    def execute_action
      case workflow_run.workflow_kind
      when WorkflowRun::KIND_CREATE_NOTA
        Workflows::Actions::CreateNota.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_CREATE_TASK
        Workflows::Actions::CreateTask.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        Workflows::Actions::CreateCalendarEvent.new(workflow_run: workflow_run).call
      else
        raise ArgumentError, "Unsupported workflow kind: #{workflow_run.workflow_kind}"
      end
    end

    def handle_failure(error)
      if AutomationControl.current.enabled? && workflow_run.attempts_count < workflow_run.max_attempts
        workflow_run.update!(
          status: WorkflowRun::STATUS_QUEUED,
          error_message: error.message,
          metadata_json: workflow_run.metadata_json.to_h.merge(
            "last_retry_scheduled_at" => Time.current.iso8601,
            "last_error_class" => error.class.name
          )
        )
        AuditEventLogger.log_workflow_run!(
          workflow_run,
          action: "workflow_run_retry_scheduled",
          metadata: { error_class: error.class.name, error_message: error.message }
        )
        Workflows::ExecuteRunJob.set(wait: RETRY_DELAY).perform_later(workflow_run.id)
      else
        workflow_run.update!(
          status: AutomationControl.current.enabled? ? WorkflowRun::STATUS_FAILED : WorkflowRun::STATUS_KILLED,
          finished_at: Time.current,
          error_message: error.message
        )
        AuditEventLogger.log_workflow_run!(
          workflow_run,
          action: workflow_run.killed? ? "workflow_run_killed" : "workflow_run_failed",
          metadata: { error_class: error.class.name, error_message: error.message }
        )
        Workflows::NotificationService.new(workflow_run: workflow_run).notify_failed! unless workflow_run.killed?
      end

      workflow_run
    end

    def kill_if_disabled!
      return if AutomationControl.current.enabled?

      workflow_run.update!(
        status: WorkflowRun::STATUS_KILLED,
        finished_at: Time.current,
        error_message: "Automation kill switch is active"
      )
      AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_killed", metadata: { reason: "kill_switch" })
      raise StandardError, "Automation kill switch is active"
    end
  end
end
