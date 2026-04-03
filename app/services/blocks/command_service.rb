module Blocks
  class CommandService
    TURN_INTO_BLOCK_TYPE_MAP = {
      "text" => "paragraph",
      "heading_1" => "heading_1",
      "heading_2" => "heading_2",
      "heading_3" => "heading_3",
      "heading_4" => "heading_4",
      "bulleted_list" => "bullet_list",
      "numbered_list" => "ordered_list",
      "todo_list" => "todo_list",
      "toggle_list" => "toggle_list",
      "code" => "code_block",
      "quote" => "blockquote",
      "callout" => "callout",
      "block_equation" => "equation",
      "toggle_heading_1" => "toggle_heading_1",
      "toggle_heading_2" => "toggle_heading_2",
      "toggle_heading_3" => "toggle_heading_3",
      "columns_2" => "columns_2",
      "columns_3" => "columns_3",
      "columns_4" => "columns_4",
      "columns_5" => "columns_5"
    }.freeze
    COLOR_ALLOWLIST = %w[default gray brown orange yellow green blue purple pink red].freeze
    HIGHLIGHT_ALLOWLIST = %w[default peach lemon mint sky lavender rose].freeze

    def self.call(block:, page:, workspace:, actor:, command:, target:, color:, highlight:, target_page:, target_database:, note:)
      new(
        block:,
        page:,
        workspace:,
        actor:,
        command:,
        target:,
        color:,
        highlight:,
        target_page:,
        target_database:,
        note:
      ).call
    end

    def initialize(block:, page:, workspace:, actor:, command:, target:, color:, highlight:, target_page:, target_database:, note:)
      @block = block
      @page = page
      @workspace = workspace
      @actor = actor
      @command = command.to_s
      @target = target.to_s
      @color = color.to_s
      @highlight = highlight.to_s
      @target_page = target_page
      @target_database = target_database
      @note = note.to_s
      @focus_anchor = "block_#{block.id}"
      @redirect_page_id = nil
      @split_page_id = nil
      @split_source = nil
      @notice = nil
      @synced_source_block = nil
    end

    def call
      case command
      when "turn_into"
        turn_into!
      when "color"
        update_color!
      when "highlight"
        update_highlight!
      when "duplicate"
        duplicate!
      when "move_to"
        move_to_page!
      when "create_linked_nota"
        create_linked_nota!
      when "link_existing_nota"
        link_existing_nota!
      when "create_linked_grid"
        create_linked_grid!
      when "link_existing_grid"
        link_existing_grid!
      when "delete"
        delete_block!
      when "insert_media"
        insert_media!
      when "suggest_edits"
        suggest_edits!
      when "copy_link", "ask_ai"
        @notice = "Action available."
      else
        raise ArgumentError, "Unsupported block command."
      end

      {
        focus_anchor: focus_anchor,
        redirect_page_id: redirect_page_id,
        split_page_id: split_page_id,
        split_source: split_source,
        notice: notice || "Block updated.",
        synced_source_block: synced_source_block
      }
    end

    private

    attr_reader :block, :page, :workspace, :actor, :command, :target, :color, :highlight, :target_page, :note,
                :target_database, :focus_anchor, :redirect_page_id, :split_page_id, :split_source, :notice, :synced_source_block

    def turn_into!
      case target
      when "page"
        create_page_from_block!(parent_page: nil)
      when "page_in"
        create_page_from_block!(parent_page: page)
      when "synced_block"
        create_synced_block!
      else
        mapped_type = TURN_INTO_BLOCK_TYPE_MAP[target]
        raise ArgumentError, "Unsupported turn-into target." if mapped_type.blank?

        if %w[image video file].include?(block.block_type) && mapped_type.start_with?("columns_")
          update_media_layout!(mapped_type)
          return
        end

        mapped_type = "paragraph" if mapped_type == block.block_type

        payload = build_content_payload_for(mapped_type)
        block.update!(block_type: mapped_type, content_json: payload)
        @notice = "Block updated."
        @synced_source_block = synced_root_for(block)
      end
    end

    def update_color!
      selected = COLOR_ALLOWLIST.include?(color) ? color : "default"
      current = block.color.presence || "default"
      selected = "default" if selected == current
      payload = deep_dup_json(block.content_json)
      payload["notae_color"] = selected
      block.update!(content_json: payload)
      @notice = "Color updated."
      @synced_source_block = synced_root_for(block)
    end

    def update_highlight!
      selected = HIGHLIGHT_ALLOWLIST.include?(highlight) ? highlight : "default"
      current = block.highlight_color.presence || "default"
      selected = "default" if selected == current
      payload = deep_dup_json(block.content_json)
      payload["notae_highlight"] = selected
      block.update!(content_json: payload)
      @notice = "Highlight updated."
      @synced_source_block = synced_root_for(block)
    end

    def duplicate!
      duplicate_root = Blocks::DuplicateService.call(block:, actor:)
      @focus_anchor = "block_#{duplicate_root.id}"
      @notice = "Block duplicated."
    end

    def move_to_page!
      raise ArgumentError, "Target page is required." if target_page.blank?

      ids = block.archiveable_tree_ids
      now = Time.current
      destination_position = (
        Block.active.where(page_id: target_page.id, parent_block_id: nil).where.not(id: ids).maximum(:position) || 0
      ) + Block::POSITION_GAP

      Block.where(id: ids - [ block.id ]).update_all(
        page_id: target_page.id,
        workspace_id: target_page.workspace_id,
        updated_at: now
      )

      block.update!(
        page: target_page,
        workspace: target_page.workspace,
        parent_block_id: nil,
        position: destination_position
      )

      Block.where(id: ids).find_each { |moved_block| PageLinks::SyncFromBlockService.call(block: moved_block) }

      @redirect_page_id = target_page.id
      @focus_anchor = "block_#{block.id}"
      @notice = "Block moved."
      @synced_source_block = synced_root_for(block)
    end

    def create_linked_nota!
      linked_page = workspace.pages.create!(
        title: next_linked_page_title,
        created_by: actor
      )

      replace_block_with_split_link!(label: linked_page.title, target_page: linked_page)
      @notice = "Linked Nota created."
    end

    def link_existing_nota!
      raise ArgumentError, "Select a Nota to link." if target_page.blank?
      raise ArgumentError, "Choose a different Nota to link." if target_page.id == page.id

      replace_block_with_split_link!(label: target_page.title, target_page: target_page)
      @notice = "Linked Nota added."
    end

    def create_linked_grid!
      database = workspace.databases.create!(
        name: next_available_database_name(extract_text(block.content_json).presence || "Untitled grid"),
        created_by: actor
      )
      linked_page = Databases::EnsureLinkedPageService.call(database:, actor:)

      replace_block_with_split_link!(label: database.name, target_page: linked_page)
      @notice = "Linked Grid created."
    end

    def link_existing_grid!
      raise ArgumentError, "Select a Grid to link." if target_database.blank?

      linked_page = Databases::EnsureLinkedPageService.call(database: target_database, actor:)

      replace_block_with_split_link!(label: target_database.name, target_page: linked_page)
      @notice = "Linked Grid added."
    end

    def delete_block!
      Blocks::ArchiveService.call(block:)
      @focus_anchor = nil
      @notice = "Block deleted."
      @synced_source_block = synced_root_for(block)
    end

    def insert_media!
      new_block_type =
        case target
        when "image", "video", "file", "media" then "file"
        else
          raise ArgumentError, "Unsupported media target."
        end

      inserted_block = block.page.blocks.create!(
        workspace: block.workspace,
        page: block.page,
        parent_block: block.parent_block,
        created_by: actor,
        block_type: new_block_type
      )

      Blocks::ReorderService.call(
        block: inserted_block,
        target_parent_id: block.parent_block_id,
        target_index: sibling_index_for(block) + 1
      )

      @focus_anchor = "block_#{inserted_block.id}"
      @notice = "Media block added."
    end

    def update_media_layout!(mapped_type)
      payload = deep_dup_json(block.content_json)
      selected_count = mapped_type.split("_").last.to_i

      if block.layout_columns_count == selected_count
        payload.delete("notae_columns_count")
      else
        payload["notae_columns_count"] = selected_count
      end

      block.update!(content_json: payload)
      @notice = "Block updated."
      @synced_source_block = synced_root_for(block)
    end

    def suggest_edits!
      Comment.create!(
        workspace: block.workspace,
        commentable: block,
        author: actor,
        body: note.presence || "Suggestion: revise this block for clarity and tone."
      )
      @notice = "Suggestion saved."
    end

    def create_page_from_block!(parent_page:)
      title = extract_text(block.content_json).presence || "Untitled page"
      new_page = workspace.pages.create!(
        parent_page: parent_page,
        title: title.first(120),
        created_by: actor
      )

      payload = deep_dup_json(block.content_json)
      payload["type"] = "doc"
      payload["content"] = [
        {
          "type" => "paragraph",
          "content" => [ { "type" => "text", "text" => "[[#{new_page.title}]]" } ]
        }
      ]
      payload.delete("notae_synced_source_id")
      block.update!(block_type: "paragraph", content_json: payload)

      @redirect_page_id = new_page.id
      @focus_anchor = nil
      @notice = "Page created from block."
      @synced_source_block = synced_root_for(block)
    end

    def replace_block_with_split_link!(label:, target_page:)
      payload = deep_dup_json(block.content_json).slice("notae_color", "notae_highlight")
      payload["type"] = "doc"
      payload["content"] = [
        paragraph_link_node(
          label:,
          href: split_preview_href_for(target_page),
          link_attrs: { "target" => "_self", "rel" => nil }
        )
      ]
      payload.delete("notae_synced_source_id")

      block.update!(block_type: "paragraph", content_json: payload)

      @redirect_page_id = page.id
      @split_page_id = target_page.id
      @split_source = "block"
      @focus_anchor = "block_#{block.id}"
      @synced_source_block = synced_root_for(block)
    end

    def create_synced_block!
      source_payload = deep_dup_json(block.content_json)
      source_payload["notae_synced_source_id"] = block.id.to_s
      block.update!(block_type: "synced_block", content_json: source_payload)

      duplicate = block.page.blocks.create!(
        workspace: block.workspace,
        page: block.page,
        parent_block: block.parent_block,
        created_by: actor,
        block_type: "synced_block",
        content_json: deep_dup_json(source_payload),
        embed_url: block.embed_url
      )

      duplicate.asset.attach(block.asset.blob) if block.asset.attached?

      @focus_anchor = "block_#{duplicate.id}"
      @notice = "Synced block created."
      @synced_source_block = block
    end

    def synced_root_for(candidate)
      source_id = candidate.synced_source_block_id
      return candidate if source_id.blank? || source_id.to_s == candidate.id.to_s

      Block.find_by(id: source_id) || candidate
    end

    def build_content_payload_for(mapped_type)
      metadata = deep_dup_json(block.content_json).slice("notae_color", "notae_highlight")
      lines = extract_lines(block.content_json)

      payload = {
        "type" => "doc",
        "content" => [ build_primary_node(mapped_type, lines) ]
      }

      if mapped_type.start_with?("columns_")
        payload["notae_columns_count"] = mapped_type.split("_").last.to_i
      end

      payload.merge(metadata)
    end

    def build_primary_node(mapped_type, lines)
      normalized_lines = normalize_lines(lines)
      text = normalized_lines.join(" ").squish

      case mapped_type
      when "heading_1" then heading_node(1, text)
      when "heading_2" then heading_node(2, text)
      when "heading_3" then heading_node(3, text)
      when "heading_4" then heading_node(4, text)
      when "bullet_list" then list_node("bulletList", normalized_lines)
      when "ordered_list" then list_node("orderedList", normalized_lines)
      when "todo_list" then task_list_node(normalized_lines)
      when "code_block"
        code_block_node(normalized_lines)
      when "blockquote"
        { "type" => "blockquote", "content" => [ paragraph_node(normalized_lines) ] }
      else
        paragraph_node(normalized_lines)
      end
    end

    def heading_node(level, text)
      {
        "type" => "heading",
        "attrs" => { "level" => level },
        "content" => [ { "type" => "text", "text" => text } ]
      }
    end

    def list_node(list_type, lines)
      {
        "type" => list_type,
        "content" => normalize_lines(lines).map do |line|
          {
            "type" => "listItem",
            "content" => [ paragraph_node([ line ]) ]
          }
        end
      }
    end

    def task_list_node(lines)
      {
        "type" => "taskList",
        "content" => normalize_lines(lines).map do |line|
          {
            "type" => "taskItem",
            "attrs" => { "checked" => false },
            "content" => [ paragraph_node([ line ]) ]
          }
        end
      }
    end

    def code_block_node(lines)
      text = normalize_lines(lines).join("\n")
      {
        "type" => "codeBlock",
        "content" => text.present? ? [ { "type" => "text", "text" => text } ] : []
      }
    end

    def paragraph_node(lines)
      segments = []
      normalize_lines(lines).each_with_index do |line, index|
        segments << { "type" => "text", "text" => line } if line.present?
        segments << { "type" => "hardBreak" } if index < normalize_lines(lines).length - 1
      end

      node = { "type" => "paragraph" }
      node["content"] = segments if segments.any?
      node
    end

    def paragraph_link_node(label:, href:, link_attrs: {})
      {
        "type" => "paragraph",
        "content" => [
          {
            "type" => "text",
            "text" => label,
            "marks" => [
              {
                "type" => "link",
                "attrs" => { "href" => href }.merge(link_attrs)
              }
            ]
          }
        ]
      }
    end

    def extract_text(node)
      collector = []
      traverse(node, collector)
      collector.join(" ").squish
    end

    def extract_lines(node)
      lines =
        case node
        when Hash
          extract_lines_from_hash(node)
        when Array
          node.flat_map { |child| extract_lines(child) }
        else
          []
        end

      normalize_lines(lines)
    end

    def extract_lines_from_hash(node)
      case node["type"].to_s
      when "doc", "blockquote", "listItem", "taskItem"
        Array(node["content"]).flat_map { |child| extract_lines(child) }
      when "bulletList", "orderedList", "taskList"
        Array(node["content"]).flat_map { |child| extract_lines(child) }
      when "paragraph", "heading"
        extract_inline_lines(node["content"])
      when "codeBlock"
        Array(node["content"]).filter_map { |child| child.is_a?(Hash) ? child["text"] : nil }.join.split(/\r?\n/, -1)
      when "text"
        [ node["text"].to_s ]
      else
        Array(node["content"]).flat_map { |child| extract_lines(child) }
      end
    end

    def extract_inline_lines(nodes)
      lines = [ "" ]

      Array(nodes).each do |child|
        next unless child.is_a?(Hash)

        case child["type"].to_s
        when "text"
          lines[-1] << child["text"].to_s
        when "hardBreak"
          lines << ""
        else
          nested_lines = extract_lines(child)
          next if nested_lines.empty?

          lines[-1] << nested_lines.shift.to_s
          nested_lines.each { |line| lines << line.to_s }
        end
      end

      lines
    end

    def normalize_lines(lines)
      normalized = Array(lines).map { |line| line.to_s.gsub(/\r\n?/, "\n").strip }
      normalized.reject!(&:blank?)
      normalized.presence || [ "" ]
    end

    def traverse(node, collector)
      case node
      when Hash
        collector << node["text"] if node["text"].is_a?(String)
        node.each do |key, value|
          next if key.to_s.start_with?("notae_")

          traverse(value, collector)
        end
      when Array
        node.each { |child| traverse(child, collector) }
      end
    end

    def deep_dup_json(value)
      return value.deep_dup if value.respond_to?(:deep_dup)

      JSON.parse(value.to_json)
    end

    def next_linked_page_title
      extract_text(block.content_json).presence&.first(120) || "Untitled nota"
    end

    def next_available_database_name(base_name)
      candidate = base_name.to_s.strip.presence || "Untitled grid"
      return candidate unless workspace.databases.exists?(name: candidate)

      suffix = 2
      loop do
        next_candidate = "#{candidate} #{suffix}"
        return next_candidate unless workspace.databases.exists?(name: next_candidate)

        suffix += 1
      end
    end

    def split_preview_href_for(target_page)
      Rails.application.routes.url_helpers.page_path(
        workspace_slug: workspace.slug,
        id: page.id,
        split_page_id: target_page.id,
        split_source: "block"
      )
    end

    def sibling_index_for(target_block)
      siblings = Block.active.where(page_id: target_block.page_id, parent_block_id: target_block.parent_block_id).ordered.to_a
      siblings.index { |sibling| sibling.id == target_block.id } || siblings.length
    end
  end
end
