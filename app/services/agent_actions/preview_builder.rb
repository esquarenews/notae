module AgentActions
  class PreviewBuilder
    FIELD_DEFINITIONS = {
      "email_draft" => [
        [ "title", "Draft title" ],
        [ "to", "To" ],
        [ "cc", "CC" ],
        [ "subject", "Subject" ],
        [ "body", "Body" ]
      ],
      "github_comment_draft" => [
        [ "title", "Draft title" ],
        [ "repository", "Repository" ],
        [ "target_reference", "Target" ],
        [ "body", "Comment" ]
      ],
      "task_ticket" => [
        [ "title", "Draft title" ],
        [ "project", "Project / Queue" ],
        [ "assignee", "Assignee" ],
        [ "due_at", "Due" ],
        [ "body", "Details" ]
      ],
      "calendar_hold" => [
        [ "title", "Draft title" ],
        [ "starts_at", "Starts" ],
        [ "ends_at", "Ends" ],
        [ "attendees", "Attendees" ],
        [ "body", "Notes" ]
      ],
      "nota_draft" => [
        [ "title", "Draft title" ],
        [ "body", "Content" ]
      ]
    }.freeze

    def initialize(agent_action)
      @agent_action = agent_action
    end

    class << self
      def build_preview(draft_type:, title:, payload:, before_snapshot: nil)
        normalized_before = Array(before_snapshot).presence
        after_snapshot = snapshot_for(draft_type:, title:, payload:)

        {
          "mode" => normalized_before.present? ? "update" : "create",
          "before" => normalized_before,
          "after" => after_snapshot,
          "changes" => build_changes(before_snapshot: normalized_before, after_snapshot: after_snapshot)
        }
      end

      def snapshot_for(draft_type:, title:, payload:)
        field_definitions_for(draft_type).map do |key, label|
          {
            "key" => key,
            "label" => label,
            "value" => normalized_value_for(key:, title:, payload:)
          }
        end
      end

      private

      def build_changes(before_snapshot:, after_snapshot:)
        if before_snapshot.blank?
          Array(after_snapshot).filter_map do |entry|
            next if entry["value"].blank?

            entry.merge("before" => nil, "after" => entry["value"])
          end
        else
          after_snapshot.filter_map do |entry|
            previous_entry = before_snapshot.find { |candidate| candidate["key"] == entry["key"] }
            before_value = previous_entry&.dig("value").to_s
            after_value = entry["value"].to_s
            next if before_value == after_value

            entry.merge("before" => before_value, "after" => after_value)
          end
        end
      end

      def field_definitions_for(draft_type)
        FIELD_DEFINITIONS.fetch(draft_type, [])
      end

      def normalized_value_for(key:, title:, payload:)
        raw_value =
          if key == "title"
            title
          else
            payload[key]
          end

        case raw_value
        when Array
          raw_value.map { |value| value.to_s.strip }.reject(&:blank?).join(", ")
        else
          raw_value.to_s.strip
        end
      end
    end

    def to_h
      self.class.build_preview(
        draft_type: agent_action.draft_type,
        title: agent_action.title,
        payload: agent_action.payload,
        before_snapshot: previous_snapshot
      )
    end

    private

    attr_reader :agent_action

    def previous_snapshot
      latest_update_event = agent_action.review_history.reverse.find { |event| event.event_type == "draft_updated" }
      snapshot = latest_update_event&.details_json&.dig("preview_before")
      return snapshot if snapshot.present?

      nil
    end
  end
end
