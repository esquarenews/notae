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
end
