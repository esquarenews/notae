module Notae
  class RecordRequestPerformanceJob < ApplicationJob
    queue_as :default

    def perform(workspace_id, sample)
      RequestPerformanceStore.record!(workspace_id:, sample:)
    end
  end
end
