module Blocks
  class CommandService
    TURN_INTO_BLOCK_TYPE_MAP = {
      "text" => "paragraph",
      "heading_1" => "heading_1",
      "heading_2" => "heading_2",
      "heading_3" => "heading_3",
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

    def self.call(block:, page:, workspace:, actor:, command:, target:, color:, target_page:, note:)
      new(
        block:,
        page:,
        workspace:,
        actor:,
        command:,
        target:,
        color:,
        target_page:,
        note:
      ).call
    end

    def initialize(block:, page:, workspace:, actor:, command:, target:, color:, target_page:, note:)
      @block = block
      @page = page
      @workspace = workspace
      @actor = actor
      @command = command.to_s
      @target = target.to_s
      @color = color.to_s
      @target_page = target_page
      @note = note.to_s
      @focus_anchor = "block_#{block.id}"
      @redirect_page_id = nil
      @notice = nil
      @synced_source_block = nil
    end

    def call
      case command
      when "turn_into"
        turn_into!
      when "color"
        update_color!
      when "duplicate"
        duplicate!
      when "move_to"
        move_to_page!
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
        notice: notice || "Block updated.",
        synced_source_block: synced_source_block
      }
    end

    private

    attr_reader :block, :page, :workspace, :actor, :command, :target, :color, :target_page, :note,
                :focus_anchor, :redirect_page_id, :notice, :synced_source_block

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

    def delete_block!
      Blocks::ArchiveService.call(block:)
      @focus_anchor = nil
      @notice = "Block deleted."
      @synced_source_block = synced_root_for(block)
    end

    def insert_media!
      new_block_type =
        case target
        when "image" then "image"
        when "video" then "video"
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
      @notice = "#{new_block_type.titleize} block added."
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
      metadata = deep_dup_json(block.content_json).slice("notae_color")
      text = extract_text(block.content_json)

      payload = {
        "type" => "doc",
        "content" => [ build_primary_node(mapped_type, text) ]
      }

      if mapped_type.start_with?("columns_")
        payload["notae_columns_count"] = mapped_type.split("_").last.to_i
      end

      payload.merge(metadata)
    end

    def build_primary_node(mapped_type, text)
      case mapped_type
      when "heading_1" then heading_node(1, text)
      when "heading_2" then heading_node(2, text)
      when "heading_3" then heading_node(3, text)
      when "bullet_list" then list_node("bulletList", text)
      when "ordered_list" then list_node("orderedList", text)
      when "code_block"
        { "type" => "codeBlock", "content" => [ { "type" => "text", "text" => text } ] }
      when "blockquote"
        { "type" => "blockquote", "content" => [ paragraph_node(text) ] }
      else
        paragraph_node(text)
      end
    end

    def heading_node(level, text)
      {
        "type" => "heading",
        "attrs" => { "level" => level },
        "content" => [ { "type" => "text", "text" => text } ]
      }
    end

    def list_node(list_type, text)
      {
        "type" => list_type,
        "content" => [
          {
            "type" => "listItem",
            "content" => [ paragraph_node(text) ]
          }
        ]
      }
    end

    def paragraph_node(text)
      {
        "type" => "paragraph",
        "content" => [ { "type" => "text", "text" => text } ]
      }
    end

    def extract_text(node)
      collector = []
      traverse(node, collector)
      collector.join(" ").squish
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

    def sibling_index_for(target_block)
      siblings = Block.active.where(page_id: target_block.page_id, parent_block_id: target_block.parent_block_id).ordered.to_a
      siblings.index { |sibling| sibling.id == target_block.id } || siblings.length
    end
  end
end
