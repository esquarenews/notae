module Search
  class KnowledgeSuggestionMaterializerService
    def initialize(suggestion:, actor:)
      @suggestion = suggestion
      @actor = actor
    end

    def create_nota!
      page = suggestion.workspace.pages.create!(
        title: nota_title,
        created_by: actor,
        page_kind: "nota"
      )

      blocks_for_nota.each_with_index do |content_json, index|
        page.blocks.create!(
          workspace: suggestion.workspace,
          created_by: actor,
          block_type: "paragraph",
          position: Block::POSITION_GAP * (index + 1),
          content_json: content_json
        )
      end

      suggestion.mark_converted!(target_type: "Page", target_id: page.id)
      page
    end

    def create_task!(database:, task_index: nil)
      task_payload = selected_task_payload(task_index)
      row = database.db_rows.create!(workspace: database.workspace, title: task_payload.fetch("title"))
      seed_task_cells!(database: database, row: row, task_payload: task_payload)
      row.sync_data_from_cells!
      suggestion.mark_converted!(target_type: "DbRow", target_id: row.id)
      row
    end

    private

    attr_reader :suggestion, :actor

    def nota_title
      base = suggestion.title.to_s.strip.presence || "Knowledge suggestion"
      "#{base} notes"
    end

    def blocks_for_nota
      sections = []
      sections << paragraph_json("Knowledge suggestion\n#{suggestion.summary}")

      insights = Array(suggestion.insights_json).map { |line| "- #{line}" }
      sections << paragraph_json("Insights\n#{insights.join("\n")}") if insights.any?

      tasks = Array(suggestion.task_suggestions_json).map do |item|
        title = item["title"].to_s.strip
        owner = item["owner"].to_s.strip.presence
        rationale = item["rationale"].to_s.strip
        line = "- #{title}"
        line += " (owner: #{owner})" if owner.present?
        line += " — #{rationale}" if rationale.present?
        line
      end
      sections << paragraph_json("Task suggestions\n#{tasks.join("\n")}") if tasks.any?

      related = Array(suggestion.related_notes_json).map do |item|
        "- #{item["title"]}: #{item["reason"]}"
      end
      sections << paragraph_json("Related notes\n#{related.join("\n")}") if related.any?

      citations = Array(suggestion.sources_json).map do |source|
        "- [#{source["index"]}] #{source["title"]} — #{source["url"]}"
      end
      sections << paragraph_json("Sources\n#{citations.join("\n")}") if citations.any?
      sections
    end

    def paragraph_json(text)
      {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => text.to_s } ]
          }
        ]
      }
    end

    def selected_task_payload(task_index)
      tasks = Array(suggestion.task_suggestions_json)
      index = task_index.to_i
      item = tasks[index] if index >= 0
      item = tasks.first if item.blank?
      item = { "title" => suggestion.title, "rationale" => suggestion.summary, "owner" => "" } if item.blank?
      item
    end

    def seed_task_cells!(database:, row:, task_payload:)
      properties = database.db_properties.ordered.to_a
      return if properties.empty?

      now = Time.current
      cells = properties.map do |property|
        {
          id: SecureRandom.uuid,
          workspace_id: database.workspace_id,
          db_row_id: row.id,
          db_property_id: property.id,
          value_text: value_for_property(property: property, task_payload: task_payload),
          created_at: now,
          updated_at: now
        }
      end
      DbCell.insert_all(cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
    end

    def value_for_property(property:, task_payload:)
      name = property.name.to_s.strip.downcase
      return "not started" if name == "status" && property.select?
      return Date.current.iso8601 if name == "date created" && property.date?
      return task_payload["owner"].to_s.strip if name.include?("owner")
      return task_payload["rationale"].to_s.strip if name == "notes"
      return "" unless property.text?

      ""
    end
  end
end
