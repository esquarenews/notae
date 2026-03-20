require "json"

module Epistularium
  class DraftSuggestionService
    REPLY = "reply".freeze
    TASK = "task_ticket".freeze
    CALENDAR = "calendar_hold".freeze
    SUPPORTED_TYPES = [ REPLY, TASK, CALENDAR ].freeze
    MODEL = Search::AssistantQueryService::WRITING_MODEL

    class Error < StandardError; end

    def initialize(user:, workspace:, message:, suggestion_type:)
      @user = user
      @workspace = workspace
      @message = message
      @suggestion_type = suggestion_type.to_s
    end

    def call
      raise Error, "OpenAI key is not configured." unless user.openai_api_key_configured?
      raise Error, "Unsupported suggestion type." unless SUPPORTED_TYPES.include?(suggestion_type)

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: prompt_for_suggestion,
        api_key: user.openai_api_key,
        model: MODEL,
        max_output_tokens: 900
      )
      parsed = parse_json_object(response[:text])
      payload = normalize_payload(parsed.fetch("payload", {}))

      agent_action = AgentActions::DraftCreator.new(
        workspace: workspace,
        actor: user,
        attributes: {
          title: parsed["title"].to_s.strip.presence || default_title_for(payload),
          proposed_by: "ai_assistant",
          target_system: target_system,
          draft_type: draft_type,
          payload_json: payload,
          metadata_json: {
            "source_email_id" => message.id,
            "source_email_subject" => message.display_subject,
            "source_email_url" => Rails.application.routes.url_helpers.workspace_epistularium_message_path(
              workspace_slug: workspace.slug,
              id: message.id
            ),
            "source_email_account_id" => message.epistularium_account_id,
            "suggestion_type" => suggestion_type,
            "model" => MODEL,
            "origin_prompt" => "AI suggestion from Epistularium"
          }
        }
      ).call

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_WRITE,
        model: MODEL,
        usage: response[:usage],
        metadata: {
          source: "epistularium_draft_suggestion",
          suggestion_type: suggestion_type,
          source_email_id: message.id
        }
      )

      agent_action
    rescue JSON::ParserError, KeyError => error
      raise Error, "AI suggestion response was invalid: #{error.message}"
    rescue Openai::ResponsesClient::Error => error
      raise Error, "AI suggestion could not be generated: #{error.message}"
    rescue AgentActions::DraftCreator::Error => error
      raise Error, error.message
    end

    private

    attr_reader :user, :workspace, :message, :suggestion_type

    def draft_type
      case suggestion_type
      when REPLY then "email_draft"
      when TASK then "task_ticket"
      else "calendar_hold"
      end
    end

    def target_system
      case suggestion_type
      when REPLY then "email"
      when TASK then "crm"
      else "calendar"
      end
    end

    def prompt_for_suggestion
      <<~PROMPT
        You are creating a draft-only action suggestion from an email.
        Return JSON only.

        Source email:
        Subject: #{message.display_subject}
        From: #{message.from_display}
        To: #{recipients_line(message.to_recipients_json)}
        CC: #{recipients_line(message.cc_recipients_json)}
        Sent at: #{message.sent_at&.iso8601}
        Received at: #{message.received_at&.iso8601}
        Body:
        #{message.body_text.to_s.strip.truncate(8000)}

        #{instructions_for_type}
      PROMPT
    end

    def instructions_for_type
      case suggestion_type
      when REPLY
        <<~PROMPT
          Create a reply draft.
          Output shape:
          {
            "title": "short draft label",
            "payload": {
              "to": ["recipient@example.com"],
              "cc": ["optional@example.com"],
              "subject": "Re: original subject",
              "body": "reply body"
            }
          }
          Keep the tone helpful and specific. Do not invent commitments that are unsupported by the email.
        PROMPT
      when TASK
        <<~PROMPT
          Create a task ticket draft.
          Output shape:
          {
            "title": "short draft label",
            "payload": {
              "project": "Inbox",
              "assignee": "",
              "due_at": "",
              "title": "task title",
              "body": "task details"
            }
          }
          Prefer a concrete next step and use "Inbox" as project if no stronger destination is clear.
        PROMPT
      else
        <<~PROMPT
          Create a calendar hold draft.
          Output shape:
          {
            "title": "short draft label",
            "payload": {
              "title": "meeting title",
              "starts_at": "YYYY-MM-DDTHH:MM",
              "ends_at": "YYYY-MM-DDTHH:MM",
              "attendees": ["person@example.com"],
              "body": "meeting notes"
            }
          }
          If the email does not specify a time, choose the next business day at 09:00 for a one-hour hold and mention that it is a placeholder in the body.
        PROMPT
      end
    end

    def normalize_payload(payload)
      case suggestion_type
      when REPLY
        normalize_reply_payload(payload)
      when TASK
        normalize_task_payload(payload)
      else
        normalize_calendar_payload(payload)
      end
    end

    def normalize_reply_payload(payload)
      to_recipients = Array(payload["to"]).map(&:to_s).map(&:strip).reject(&:blank?)
      to_recipients = [ message.reply_to_recipients_json.first&.fetch("email", nil), message.from_email ].compact if to_recipients.empty?

      {
        "to" => to_recipients.uniq,
        "cc" => Array(payload["cc"]).map(&:to_s).map(&:strip).reject(&:blank?).uniq,
        "subject" => payload["subject"].to_s.strip.presence || reply_subject,
        "body" => payload["body"].to_s
      }
    end

    def normalize_task_payload(payload)
      {
        "project" => payload["project"].to_s.strip.presence || "Inbox",
        "assignee" => payload["assignee"].to_s.strip,
        "due_at" => payload["due_at"].to_s.strip,
        "title" => payload["title"].to_s.strip.presence || message.display_subject,
        "body" => payload["body"].to_s
      }
    end

    def normalize_calendar_payload(payload)
      starts_at = normalize_calendar_time(payload["starts_at"])
      ends_at = normalize_calendar_time(payload["ends_at"])
      if starts_at.blank? || ends_at.blank? || Time.zone.parse(ends_at) <= Time.zone.parse(starts_at)
        starts_at, ends_at = default_calendar_window
      end

      {
        "title" => payload["title"].to_s.strip.presence || message.display_subject,
        "starts_at" => starts_at,
        "ends_at" => ends_at,
        "attendees" => Array(payload["attendees"]).map(&:to_s).map(&:strip).reject(&:blank?).presence || default_calendar_attendees,
        "body" => payload["body"].to_s.presence || "Placeholder time selected automatically from the email context."
      }
    end

    def default_title_for(payload)
      case suggestion_type
      when REPLY
        "Reply draft for #{message.display_subject}"
      when TASK
        payload["title"].to_s.presence || "Task draft from #{message.display_subject}"
      else
        "Calendar hold from #{message.display_subject}"
      end
    end

    def normalize_calendar_time(value)
      parsed = Time.zone.parse(value.to_s)
      return "" if parsed.blank?

      parsed.strftime("%Y-%m-%dT%H:%M")
    rescue ArgumentError, TypeError
      ""
    end

    def default_calendar_window
      zone = ActiveSupport::TimeZone[user.time_zone] || Time.zone
      start_time = zone.now.next_occurring(:monday).change(hour: 9, min: 0) rescue zone.now.tomorrow.change(hour: 9, min: 0)
      start_time += 1.day while start_time.saturday? || start_time.sunday?
      end_time = start_time + 1.hour
      [ start_time.strftime("%Y-%m-%dT%H:%M"), end_time.strftime("%Y-%m-%dT%H:%M") ]
    end

    def default_calendar_attendees
      [ message.from_email ].compact
    end

    def reply_subject
      return message.display_subject if message.display_subject.match?(/\ARe:/i)

      "Re: #{message.display_subject}"
    end

    def parse_json_object(raw)
      payload = raw.to_s.strip
      JSON.parse(payload[/\{.*\}/m] || payload)
    end

    def recipients_line(values)
      Array(values).filter_map do |recipient|
        next unless recipient.is_a?(Hash)

        [ recipient["name"].to_s.strip.presence, recipient["email"].to_s.strip.presence ].compact.join(" ").strip.presence
      end.join(", ")
    end
  end
end
