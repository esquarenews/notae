module Meetings
  class NotaMaterializerService
    SESSION_MARKER_KEY = "notae_meeting_session_id".freeze

    def initialize(session:, actor:)
      @session = session
      @actor = actor
    end

    def ensure_linked_nota!
      page =
        session.page ||
        session.kalendarium_event&.linked_page ||
        begin
          new_page = workspace.pages.create!(
            title: default_title,
            page_kind: "meeting_note",
            created_by: actor
          )
          new_page.blocks.create!(workspace: workspace, created_by: actor, block_type: "paragraph")
          new_page
        end

      session.update!(page: page) if session.page_id != page.id
      if session.kalendarium_event.present? && session.kalendarium_event.linked_page_id != page.id
        session.kalendarium_event.update!(linked_page: page, updated_by: actor)
      end

      page
    end

    def upsert_session_output!(transcript_text:, summary_markdown:, action_items:)
      page = ensure_linked_nota!
      remove_existing_session_blocks!(page)
      base_position = next_position_for(page)

      blocks = [
        session_heading_block,
        summary_block(summary_markdown),
        actions_block(action_items),
        transcript_block(transcript_text)
      ].compact

      blocks.each_with_index do |content_json, index|
        page.blocks.create!(
          workspace: workspace,
          created_by: actor,
          block_type: "paragraph",
          position: base_position + (index * Block::POSITION_GAP),
          content_json: content_json
        )
      end

      page.touch
      page
    end

    private

    attr_reader :session, :actor

    delegate :workspace, to: :session

    def default_title
      base = session.kalendarium_event&.title.to_s.strip.presence || session.title.to_s.strip.presence || "Meeting"
      "#{base} notes"
    end

    def remove_existing_session_blocks!(page)
      page.blocks.active.find_each do |block|
        marker = block.content_json.to_h[SESSION_MARKER_KEY].to_s
        next unless marker == session.id.to_s

        block.destroy!
      end
    end

    def next_position_for(page)
      (page.blocks.active.maximum(:position) || 0) + Block::POSITION_GAP
    end

    def session_heading_block
      timestamp = Time.current.in_time_zone(actor.time_zone).strftime("%a %-d %b %Y %H:%M")
      paragraph_json("Meeting capture processed #{timestamp}")
    end

    def summary_block(summary_markdown)
      value = summary_markdown.to_s.strip
      return nil if value.blank?

      paragraph_json("Summary\n#{value}")
    end

    def actions_block(action_items)
      items = Array(action_items).filter_map do |item|
        title = item.is_a?(Hash) ? item["title"].to_s.strip : ""
        next if title.blank?

        owner = item["owner"].to_s.strip.presence
        due_at = item["due_at"].to_s.strip.presence
        suffix = [ owner && "owner: #{owner}", due_at && "due: #{due_at}" ].compact.join(" • ")
        suffix.present? ? "- #{title} (#{suffix})" : "- #{title}"
      end
      return nil if items.empty?

      paragraph_json("Action items\n#{items.join("\n")}")
    end

    def transcript_block(transcript_text)
      value = transcript_text.to_s.strip
      return nil if value.blank?

      paragraph_json("Transcript\n#{value}")
    end

    def paragraph_json(text)
      {
        SESSION_MARKER_KEY => session.id.to_s,
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => text.to_s } ]
          }
        ]
      }
    end
  end
end
