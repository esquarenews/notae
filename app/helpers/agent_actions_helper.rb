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
  EVENT_BADGE_LABELS = {
    "policy_evaluated" => "Policy",
    "draft_created" => "Created",
    "draft_updated" => "Updated",
    "changes_requested" => "Revision",
    "resubmitted" => "Resubmitted",
    "approved" => "Approved",
    "reversed" => "Reversed",
    "rejected" => "Rejected",
    "tool_used" => "Executed",
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

  def agent_action_execution_preview(agent_action)
    preview = agent_action.result_json.to_h["execution_preview"]
    preview.is_a?(Hash) ? preview : nil
  end

  def agent_action_latest_event(agent_action)
    audit_events_for(agent_action).last
  end

  def agent_action_event_count(agent_action)
    audit_events_for(agent_action).size
  end

  def agent_action_review_chain_verified?(agent_action)
    audit_events_for(agent_action).all?(&:hash_verification_succeeds?)
  end

  def agent_action_last_activity_summary(agent_action)
    event = agent_action_latest_event(agent_action)
    return "No audit activity yet." if event.blank?

    "#{agent_action_event_title(event)} by #{agent_action_event_actor_label(event)}"
  end

  def agent_action_event_badge_label(event)
    EVENT_BADGE_LABELS[event.event_type.to_s] || "Event"
  end

  def agent_action_event_actor_label(event)
    event.actor&.email.presence || "system"
  end

  def agent_action_event_timestamp(event)
    return "Unknown time" if event.occurred_at.blank?

    "#{event.occurred_at.in_time_zone.strftime("%d %b %Y · %H:%M")} · #{time_ago_in_words(event.occurred_at)} ago"
  end

  def agent_action_event_summary(event)
    details = event.details_json.to_h

    case event.event_type
    when "policy_evaluated"
      lifecycle = humanized_agent_action_lifecycle(details["lifecycle_operation"])
      if details["allowed"]
        "Policy allowed #{lifecycle.downcase}.#{details["dry_run_only"] ? ' Workspace remains in dry-run mode.' : ''}"
      else
        "Policy blocked #{lifecycle.downcase}: #{Array(details["reasons"]).to_sentence}."
      end
    when "draft_created"
      "Draft created for #{details["target_system"].to_s.titleize.presence || 'the selected system'}."
    when "draft_updated"
      labels = agent_action_event_change_labels(event)
      labels.any? ? "Draft updated: #{labels.to_sentence}." : "Draft content was updated."
    when "changes_requested"
      event.comment.presence || "An approver requested revisions before execution."
    when "resubmitted"
      "Updated draft resubmitted for review."
    when "approved"
      event.comment.presence || "Draft approved for execution."
    when "reversed"
      details["summary"].presence || event.comment.presence || "Approved action reversed."
    when "rejected"
      event.comment.presence || "Draft rejected."
    when "tool_used"
      details["summary"].presence || "Execution adapter completed #{details["dry_run"] ? 'a dry-run' : 'a live change'}."
    when "failed"
      details["summary"].presence || details["error"].presence || event.comment.presence || "Execution failed."
    else
      event.comment.presence || "Audit event recorded."
    end
  end

  def agent_action_event_facts(event)
    details = event.details_json.to_h

    case event.event_type
    when "policy_evaluated"
      compact_agent_action_facts(
        [
          fact("Decision", details["allowed"] ? "Allowed" : "Blocked"),
          fact("Lifecycle", humanized_agent_action_lifecycle(details["lifecycle_operation"])),
          fact("Actor role", details["role"].to_s.humanize.presence),
          fact("Approval required", yes_no_label(details["approval_required"])),
          fact("Execution mode", details["dry_run_only"] ? "Dry-run only" : "Live execution allowed"),
          fact("Reasons", Array(details["reasons"]).presence&.to_sentence),
          fact("Policy id", details["policy_id"])
        ]
      )
    when "draft_created", "draft_updated"
      compact_agent_action_facts(
        [
          fact("Target system", details["target_system"].to_s.titleize.presence),
          fact("Draft type", details["draft_type"].to_s.humanize.presence),
          fact("Changed fields", agent_action_event_change_labels(event).presence&.to_sentence)
        ]
      )
    when "changes_requested", "resubmitted", "approved", "rejected"
      compact_agent_action_facts(
        [
          fact("Status", details["status"].to_s.humanize.presence)
        ]
      )
    when "tool_used"
      compact_agent_action_facts(
        [
          fact("Execution mode", details["dry_run"] ? "Dry-run" : "Live"),
          fact("Target record", agent_action_target_record_label(details)),
          fact("Changed fields", agent_action_preview_labels(details["execution_preview"]).presence&.to_sentence),
          fact("Open item", "Open created item", href: details["url"])
        ]
      )
    when "reversed"
      compact_agent_action_facts(
        [
          fact("Target record", agent_action_target_record_label(details)),
          fact("Reversed at", humanized_agent_action_timestamp(details["reversed_at"]))
        ]
      )
    when "failed"
      compact_agent_action_facts(
        [
          fact("Error", details["error"].presence || details["summary"].presence)
        ]
      )
    else
      []
    end
  end

  def agent_action_policy_facts(agent_action)
    details = agent_action.policy_evaluation_json.to_h
    return [] if details.blank?

    compact_agent_action_facts(
      [
        fact("Decision", details["allowed"] ? "Allowed" : "Blocked"),
        fact("Lifecycle", humanized_agent_action_lifecycle(details["lifecycle_operation"])),
        fact("Actor role", details["role"].to_s.humanize.presence),
        fact("Approval required", yes_no_label(details["approval_required"])),
        fact("Execution mode", details["dry_run_only"] ? "Dry-run only" : "Live execution allowed"),
        fact("Reasons", Array(details["reasons"]).presence&.to_sentence),
        fact("Policy id", details["policy_id"])
      ]
    )
  end

  def agent_action_result_facts(agent_action)
    result = agent_action.result_json.to_h
    return [] if result.blank?

    compact_agent_action_facts(
      [
        fact("Execution mode", result["dry_run"] ? "Dry-run" : "Live"),
        fact("Target record", agent_action_target_record_label(result)),
        fact("Open item", "Open created item", href: result["url"]),
        fact("Reversal", result.dig("reversal", "summary"))
      ]
    )
  end

  def agent_action_pretty_json(payload)
    JSON.pretty_generate(payload.to_h)
  rescue JSON::GeneratorError, NoMethodError
    payload.to_s
  end

  private

  def audit_events_for(agent_action)
    events =
      if agent_action.agent_action_events.loaded?
        agent_action.agent_action_events.to_a
      else
        agent_action.agent_action_events.includes(:actor).order(:sequence_number).to_a
      end

    events.sort_by(&:sequence_number)
  end

  def agent_action_event_change_labels(event)
    details = event.details_json.to_h
    before_snapshot = Array(details["preview_before"])
    after_snapshot = Array(details["preview_after"])
    return [] if after_snapshot.blank?

    if before_snapshot.blank?
      after_snapshot.filter_map do |entry|
        entry["label"] if entry["value"].to_s.strip.present?
      end
    else
      after_snapshot.filter_map do |entry|
        before_value = before_snapshot.find { |candidate| candidate["key"] == entry["key"] }&.dig("value").to_s.strip
        after_value = entry["value"].to_s.strip
        next if before_value == after_value

        entry["label"]
      end
    end
  end

  def agent_action_preview_labels(preview)
    Array(preview.to_h["changes"]).filter_map { |entry| entry["label"].presence }
  end

  def humanized_agent_action_lifecycle(value)
    value.to_s.humanize.presence || "Unknown"
  end

  def humanized_agent_action_timestamp(value)
    timestamp = Time.zone.parse(value.to_s)
    timestamp.in_time_zone.strftime("%d %b %Y · %H:%M")
  rescue ArgumentError, TypeError
    value.to_s.presence || "Unknown"
  end

  def yes_no_label(value)
    ActiveModel::Type::Boolean.new.cast(value) ? "Yes" : "No"
  end

  def agent_action_target_record_label(details)
    target_type = details["target_type"].presence
    target_id = details["target_id"].presence
    return if target_type.blank? || target_id.blank?

    "#{target_type} · #{target_id}"
  end

  def fact(label, value, href: nil)
    { label: label, value: value, href: href }
  end

  def compact_agent_action_facts(facts)
    facts.filter_map do |item|
      next if item[:value].blank?

      item
    end
  end
end
