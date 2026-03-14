module Workflows
  class ExecuteRunJob < ApplicationJob
    queue_as :default

    def perform(workflow_run_id)
      workflow_run = WorkflowRun.find(workflow_run_id)
      Workflows::Executor.new(workflow_run: workflow_run).call
    end
  end
end
