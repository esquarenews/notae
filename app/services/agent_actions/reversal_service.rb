module AgentActions
  class ReversalService
    class Error < StandardError; end

    def initialize(agent_action:, actor:, comment: nil)
      @agent_action = agent_action
      @actor = actor
      @comment = comment.to_s.strip.presence
    end

    def call
      raise Error, "This action cannot be reversed." unless agent_action.reversible?

      agent_action.transaction do
        reversal_result = reverse_target!
        updated_result = agent_action.result_json.to_h.merge("reversal" => reversal_result)

        agent_action.update!(result_json: updated_result)
        agent_action.log_event!(event_type: "reversed", actor: actor, comment: comment, details: reversal_result)
        agent_action
      end
    end

    private

    attr_reader :agent_action, :actor, :comment

    def workspace
      agent_action.workspace
    end

    def target_type
      agent_action.result_json.to_h["target_type"].to_s
    end

    def target_id
      agent_action.result_json.to_h["target_id"]
    end

    def reverse_target!
      case target_type
      when "Page"
        reverse_page!
      when "DbRow"
        reverse_db_row!
      when "KalendariumEvent"
        reverse_kalendarium_event!
      else
        raise Error, "Reversal is not supported for #{target_type.presence || 'this action'}."
      end
    end

    def reverse_page!
      page = workspace.pages.find_by(id: target_id)
      raise Error, "Created Nota could not be found." if page.blank?

      page.archive! unless page.archived?

      {
        "reversed_at" => Time.current.iso8601(6),
        "target_type" => "Page",
        "target_id" => page.id,
        "summary" => "Archived the created Nota."
      }
    end

    def reverse_db_row!
      row = workspace.db_rows.find_by(id: target_id)
      raise Error, "Created task could not be found." if row.blank?

      row.archive! unless row.archived?

      {
        "reversed_at" => Time.current.iso8601(6),
        "target_type" => "DbRow",
        "target_id" => row.id,
        "summary" => "Archived the created task."
      }
    end

    def reverse_kalendarium_event!
      event = workspace.kalendarium_events.find_by(id: target_id)
      raise Error, "Created event could not be found." if event.blank?

      event.destroy!

      {
        "reversed_at" => Time.current.iso8601(6),
        "target_type" => "KalendariumEvent",
        "target_id" => target_id,
        "summary" => "Deleted the created calendar event."
      }
    end
  end
end
