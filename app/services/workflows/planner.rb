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
          { "key" => "import_nota_markdown", "description" => "Import the requested Markdown into the nota." },
          { "key" => "read_nota", "description" => "Re-read the created nota." }
        ]
      when WorkflowRun::KIND_UPDATE_NOTA
        base_steps + [
          { "key" => "locate_nota", "description" => "Find the target nota within the actor's authorized scope." },
          { "key" => "update_nota", "description" => "Update the requested nota fields and import any supplied Markdown." },
          { "key" => "read_nota", "description" => "Re-read the updated nota." }
        ]
      when WorkflowRun::KIND_CREATE_TASK
        base_steps + [
          { "key" => "locate_database", "description" => "Find the target internal task database." },
          { "key" => "create_task_row", "description" => "Create the task row and seed matching properties." }
        ]
      when WorkflowRun::KIND_CREATE_CALENDAR_EVENT
        base_steps + [
          { "key" => "locate_writable_calendar", "description" => "Find a writable local, project, or provider calendar." },
          { "key" => "create_calendar_event", "description" => "Create the calendar event and queue provider sync when needed." }
        ]
      when WorkflowRun::KIND_CREATE_DATABASE
        base_steps + [
          { "key" => "create_database", "description" => "Create the grid with the requested generic properties and rows." },
          { "key" => "create_linked_page", "description" => "Create the grid's linked page and default table view." },
          { "key" => "read_database", "description" => "Re-read the created grid, properties, and rows." }
        ]
      else
        base_steps
      end
    end
  end
end
