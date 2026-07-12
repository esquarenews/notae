module Workflows
  class Executor
    RETRY_DELAY = 5.seconds
    RUNNING_LEASE = 15.minutes

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      return workflow_run unless claim_attempt!

      ActiveRecord::Base.transaction do
        workflow_run.lock!
        result = execute_action
        workflow_run.update!(
          status: WorkflowRun::STATUS_SUCCEEDED,
          finished_at: Time.current,
          result_json: result,
          error_message: nil
        )
        AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_succeeded", metadata: result)
      end

      workflow_run
    rescue StandardError => e
      workflow_run.reload if workflow_run.persisted?
      handle_failure(e)
    end

    private

    attr_reader :workflow_run

    def execute_action
      case workflow_run.workflow_kind
      when WorkflowRun::KIND_CREATE_NOTA
        Workflows::Actions::CreateNota.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_UPDATE_NOTA
        Workflows::Actions::UpdateNota.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_CREATE_TASK
        Workflows::Actions::CreateTask.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        Workflows::Actions::CreateCalendarEvent.new(workflow_run: workflow_run).call
      when WorkflowRun::KIND_CREATE_DATABASE
        Workflows::Actions::CreateDatabase.new(workflow_run: workflow_run).call
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

    def claim_attempt!
      outcome = :not_claimed
      lease_check_wait = nil

      workflow_run.with_lock do
        next if workflow_run.finished?

        if workflow_run.running?
          unless running_lease_expired?
            outcome = :lease_check
            lease_check_wait = [ running_lease_expires_at - Time.current, 1 ].max
            next
          end

          if workflow_run.attempts_count >= workflow_run.max_attempts
            workflow_run.update!(
              status: WorkflowRun::STATUS_FAILED,
              finished_at: Time.current,
              error_message: "Workflow execution lease expired after the final allowed attempt"
            )
            AuditEventLogger.log_workflow_run!(
              workflow_run,
              action: "workflow_run_failed",
              metadata: { reason: "running_lease_expired" }
            )
            outcome = :failed
            next
          end
        end

        unless AutomationControl.current.enabled?
          workflow_run.update!(
            status: WorkflowRun::STATUS_KILLED,
            finished_at: Time.current,
            error_message: "Automation kill switch is active"
          )
          AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_killed", metadata: { reason: "kill_switch" })
          next
        end

        workflow_run.update!(
          status: WorkflowRun::STATUS_RUNNING,
          attempts_count: workflow_run.attempts_count + 1,
          started_at: workflow_run.started_at || Time.current,
          error_message: nil,
          metadata_json: workflow_run.metadata_json.to_h.merge("attempt_claimed_at" => Time.current.iso8601)
        )
        AuditEventLogger.log_workflow_run!(workflow_run, action: "workflow_run_started")
        outcome = :claimed
      end

      Workflows::NotificationService.new(workflow_run: workflow_run).notify_failed! if outcome == :failed
      Workflows::ExecuteRunJob.set(wait: lease_check_wait).perform_later(workflow_run.id) if outcome == :lease_check
      outcome == :claimed
    end

    def running_lease_expired?
      running_lease_expires_at <= Time.current
    end

    def running_lease_expires_at
      running_lease_claimed_at + RUNNING_LEASE
    end

    def running_lease_claimed_at
      Time.zone.parse(workflow_run.metadata_json.to_h["attempt_claimed_at"].to_s) || workflow_run.updated_at
    rescue ArgumentError, TypeError
      workflow_run.updated_at
    end
  end
end
