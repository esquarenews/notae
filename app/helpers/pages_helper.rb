module PagesHelper
  BLOCK_TURN_INTO_ITEMS = [
    [ "T", "Text", "text" ],
    [ "H1", "Heading 1", "heading_1" ],
    [ "H2", "Heading 2", "heading_2" ],
    [ "H3", "Heading 3", "heading_3" ],
    [ "H4", "Heading 4", "heading_4" ],
    [ "ul", "Bulleted list", "bulleted_list" ],
    [ "1.", "Numbered list", "numbered_list" ],
    [ "[]", "To-do list", "todo_list" ],
    [ ">", "Toggle list", "toggle_list" ],
    [ "<>", "Code", "code" ],
    [ "\"\"", "Quote", "quote" ],
    [ "!", "Callout", "callout" ],
    [ "fx", "Block equation", "block_equation" ],
    [ "S", "Synced block", "synced_block" ],
    [ "||", "2 columns", "columns_2" ],
    [ "|||", "3 columns", "columns_3" ],
    [ "||||", "4 columns", "columns_4" ],
    [ "|||||", "5 columns", "columns_5" ]
  ].freeze
  BLOCK_TURN_INTO_BLOCK_TYPE_MAP = {
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
    "columns_2" => "columns_2",
    "columns_3" => "columns_3",
    "columns_4" => "columns_4",
    "columns_5" => "columns_5"
  }.freeze
  BLOCK_COLOR_ITEMS = [
    [ "Default", "default" ],
    [ "Gray", "gray" ],
    [ "Brown", "brown" ],
    [ "Orange", "orange" ],
    [ "Yellow", "yellow" ],
    [ "Green", "green" ],
    [ "Blue", "blue" ],
    [ "Purple", "purple" ],
    [ "Pink", "pink" ],
    [ "Red", "red" ]
  ].freeze
  BLOCK_HIGHLIGHT_ITEMS = [
    [ "None", "default" ],
    [ "Peach", "peach" ],
    [ "Lemon", "lemon" ],
    [ "Mint", "mint" ],
    [ "Sky", "sky" ],
    [ "Lavender", "lavender" ],
    [ "Rose", "rose" ]
  ].freeze

  def page_block_turn_into_items
    BLOCK_TURN_INTO_ITEMS
  end

  def page_block_turn_into_block_type_map
    BLOCK_TURN_INTO_BLOCK_TYPE_MAP
  end

  def page_block_color_items
    BLOCK_COLOR_ITEMS
  end

  def page_block_highlight_items
    BLOCK_HIGHLIGHT_ITEMS
  end

  def render_block_static_content(block, interactive: false)
    content = render_prosemirror_node(block.content_json)
    content = content_tag(:p, block.search_text.to_s.presence || block.block_type.to_s) if content.blank?
    options = {
      class: "ProseMirror notae-doc-static-content",
      data: { block_editor_static: true }
    }
    if interactive
      options[:tabindex] = 0
      options[:role] = "textbox"
      options[:aria] = { label: "Block content. Press Enter or start typing to edit." }
    end

    content_tag(:div, content, **options)
  end

  private

  def render_prosemirror_node(node)
    case node
    when Hash
      render_prosemirror_hash_node(node)
    when Array
      safe_join(node.map { |child| render_prosemirror_node(child) })
    else
      "".html_safe
    end
  end

  def render_prosemirror_hash_node(node)
    case node["type"].to_s
    when "doc"
      render_prosemirror_children(node)
    when "text"
      render_prosemirror_text_node(node)
    when "paragraph"
      content_tag(:p, render_prosemirror_children(node))
    when "heading"
      content_tag("h#{prosemirror_heading_level(node)}", render_prosemirror_children(node))
    when "bulletList"
      content_tag(:ul, render_prosemirror_children(node))
    when "orderedList"
      content_tag(:ol, render_prosemirror_children(node))
    when "listItem"
      content_tag(:li, render_prosemirror_children(node))
    when "taskList"
      content_tag(:ul, render_prosemirror_children(node), data: { type: "taskList" })
    when "taskItem"
      render_prosemirror_task_item(node)
    when "blockquote"
      content_tag(:blockquote, render_prosemirror_children(node))
    when "codeBlock"
      content_tag(:pre, content_tag(:code, prosemirror_plain_text(node)))
    when "hardBreak"
      tag.br
    when "horizontalRule"
      tag.hr
    else
      render_prosemirror_children(node)
    end
  end

  def render_prosemirror_children(node)
    safe_join(Array(node["content"]).map { |child| render_prosemirror_node(child) })
  end

  def render_prosemirror_text_node(node)
    rendered = ERB::Util.html_escape(node["text"].to_s)
    Array(node["marks"]).each do |mark|
      rendered = render_prosemirror_mark(rendered, mark)
    end
    rendered
  end

  def render_prosemirror_mark(content, mark)
    case mark.to_h["type"].to_s
    when "bold"
      content_tag(:strong, content)
    when "italic"
      content_tag(:em, content)
    when "strike"
      content_tag(:s, content)
    when "code"
      content_tag(:code, content)
    when "link"
      href = safe_prosemirror_href(mark.to_h.dig("attrs", "href"))
      href.present? ? link_to(content, href) : content
    else
      content
    end
  end

  def render_prosemirror_task_item(node)
    checked = ActiveModel::Type::Boolean.new.cast(node.dig("attrs", "checked"))
    checkbox = tag.input(type: "checkbox", checked: checked, disabled: true)
    label = content_tag(:label, checkbox + tag.span)
    body = content_tag(:div, render_prosemirror_children(node))

    content_tag(:li, label + body, data: { type: "taskItem", checked: checked.to_s })
  end

  def prosemirror_heading_level(node)
    level = node.dig("attrs", "level").to_i
    level.clamp(1, 6)
  end

  def prosemirror_plain_text(node)
    return node["text"].to_s if node["type"].to_s == "text"

    Array(node["content"]).map { |child| prosemirror_plain_text(child) }.join
  end

  def safe_prosemirror_href(value)
    raw = value.to_s.strip
    return if raw.blank?
    return raw if raw.start_with?("/") && !raw.start_with?("//")

    uri = URI.parse(raw)
    return raw if %w[http https mailto].include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end
end
