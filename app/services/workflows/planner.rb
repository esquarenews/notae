module Workflows
  class Planner
    def initialize(workflow_kind:, input:)
      @workflow_kind = workflow_kind.to_s
      @input = input.to_h.stringify_keys
    end

    def call
      {
        "workflow_kind" => workflow_kind,
        "steps" => steps_for_kind
      }
    end

    private

    attr_reader :workflow_kind, :input

    def steps_for_kind
      base_steps = [
        { "key" => "validate_inputs", "description" => "Validate workflow inputs and target access." }
      ]

      case workflow_kind
      when WorkflowRun::KIND_CREATE_NOTA
        base_steps + [
          { "key" => "create_nota_page", "description" => "Create a nota page in the workspace." },
          { "key" => "write_nota_content", "description" => "Write the requested nota content into the page." }
        ]
      when WorkflowRun::KIND_CREATE_TASK
        base_steps + [
          { "key" => "locate_database", "description" => "Find the target internal task database." },
          { "key" => "create_task_row", "description" => "Create the task row and seed matching properties." }
        ]
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        base_steps + [
          { "key" => "locate_internal_calendar", "description" => "Find a local or project calendar." },
          { "key" => "create_calendar_event", "description" => "Create the internal calendar event." }
        ]
      else
        base_steps
      end
    end
  end
end
