module AgentActionsHelper
  EVENT_TITLES = {
    "policy_evaluated" => "Policy evaluated",
    "draft_created" => "Draft created",
    "draft_updated" => "Draft updated",
    "changes_requested" => "Changes requested",
    "resubmitted" => "Resubmitted for review",
    "approved" => "Approved",
    "reversed" => "Reversed",
    "rejected" => "Rejected",
    "tool_used" => "Dry-run adapter used",
    "failed" => "Failed"
  }.freeze

  def agent_action_payload_value(agent_action, key)
    agent_action.payload_json.to_h[key.to_s]
  end

  def agent_action_payload_lines(agent_action, key)
    Array(agent_action_payload_value(agent_action, key)).join("\n")
  end

  def agent_action_status_badge(agent_action)
    case agent_action.status
    when AgentAction::STATUS_CHANGES_REQUESTED then "Changes Requested"
    when AgentAction::STATUS_APPROVED then "Approved"
    when AgentAction::STATUS_REJECTED then "Rejected"
    when AgentAction::STATUS_FAILED then "Failed"
    else "Pending"
    end
  end

  def agent_action_event_title(event)
    EVENT_TITLES[event.event_type.to_s] || event.event_type.to_s.humanize
  end

  def agent_action_preview_summary(agent_action)
    payload = agent_action.payload
    case agent_action.draft_type
    when "email_draft"
      recipients = (Array(payload["to"]) + Array(payload["cc"])).first(2).join(", ")
      [
        payload["subject"].presence || "Untitled email",
        recipients.presence
      ].compact.join(" · ")
    when "github_comment_draft"
      [ payload["repository"], payload["target_reference"] ].compact_blank.join(" · ")
    when "calendar_hold"
      [ payload["title"], payload["starts_at"] ].compact_blank.join(" · ")
    else
      [ payload["project"], payload["title"] ].compact_blank.join(" · ")
    end
  end

  def agent_action_target_matrix_json
    AgentAction::TARGET_SYSTEMS_BY_DRAFT_TYPE.to_json
  end

  def agent_action_preview_data(agent_action)
    AgentActions::PreviewBuilder.new(agent_action).to_h
  end
end
