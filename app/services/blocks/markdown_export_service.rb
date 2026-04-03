module Blocks
  class MarkdownExportService
    class << self
      def call(block:)
        new(block: block).call
      end
    end

    def initialize(block:)
      @block = block
    end

    def call
      normalize_lines(markdown_lines_for_block(block: block, depth: 0))
    end

    private

    attr_reader :block

    def markdown_lines_for_block(block:, depth:)
      if attachment_block?(block)
        return attachment_lines_for(block: block, depth: depth)
      end

      if block.block_type.to_s == "embed"
        return [] if block.embed_url.blank?

        return [ "#{indent(depth)}[Embedded content](#{block.embed_url})" ]
      end

      rendered = render_document(node: block.content_json, depth: depth)
      return rendered if rendered.any?

      fallback_text = extract_plain_text(block.content_json)
      return [] if fallback_text.blank?

      if block.block_type.to_s.start_with?("heading_")
        level = block.block_type.to_s.split("_").last.to_i.clamp(1, 6)
        [ "#{indent(depth)}#{'#' * level} #{fallback_text}" ]
      else
        [ "#{indent(depth)}#{fallback_text}" ]
      end
    end

    def attachment_block?(block)
      %w[image video file].include?(block.block_type.to_s)
    end

    def attachment_lines_for(block:, depth:)
      return [] unless block.asset.attached?

      prefix =
        case block.block_type.to_s
        when "image" then "Image"
        when "video" then "Video"
        else "Attachment"
        end

      [ "#{indent(depth)}#{prefix}: #{block.asset.filename}" ]
    end

    def render_document(node:, depth:)
      case node
      when Hash
        if node["type"] == "doc"
          render_block_nodes(nodes: Array(node["content"]), depth: depth)
        else
          render_block_nodes(nodes: [ node ], depth: depth)
        end
      when Array
        render_block_nodes(nodes: node, depth: depth)
      else
        []
      end
    end

    def render_block_nodes(nodes:, depth:)
      nodes.flat_map do |node|
        render_block_node(node: node, depth: depth)
      end
    end

    def render_block_node(node:, depth:)
      return [] unless node.is_a?(Hash)

      case node["type"]
      when "heading"
        text = render_inline_nodes(Array(node["content"]))
        return [] if text.blank?

        level = node.dig("attrs", "level").to_i.clamp(1, 6)
        [ "#{indent(depth)}#{'#' * level} #{text}" ]
      when "paragraph"
        text = render_inline_nodes(Array(node["content"]))
        return [] if text.blank?

        [ "#{indent(depth)}#{text}" ]
      when "bulletList"
        render_list(node: node, depth: depth, ordered: false)
      when "orderedList"
        render_list(node: node, depth: depth, ordered: true)
      when "taskList"
        render_task_list(node: node, depth: depth)
      when "blockquote"
        render_blockquote(node: node, depth: depth)
      when "codeBlock"
        render_code_block(node: node, depth: depth)
      else
        if node["content"].is_a?(Array)
          render_block_nodes(nodes: node["content"], depth: depth)
        else
          []
        end
      end
    end

    def render_list(node:, depth:, ordered:)
      start = node.dig("attrs", "start").to_i
      start = 1 if start <= 0

      Array(node["content"]).each_with_index.flat_map do |item, index|
        render_list_item(item: item, depth: depth, ordered: ordered, number: start + index)
      end
    end

    def render_task_list(node:, depth:)
      Array(node["content"]).flat_map do |item|
        render_task_item(item: item, depth: depth)
      end
    end

    def render_task_item(item:, depth:)
      return [] unless item.is_a?(Hash)

      checked = item.dig("attrs", "checked") ? "x" : " "
      children = Array(item["content"])
      first_paragraph = children.find { |child| child.is_a?(Hash) && child["type"] == "paragraph" }
      first_text = first_paragraph ? render_inline_nodes(Array(first_paragraph["content"])) : render_inline_nodes(children)
      lines = [ "#{indent(depth)}- [#{checked}] #{first_text}".rstrip ]

      remaining = children.dup
      if first_paragraph
        first_index = remaining.index(first_paragraph)
        remaining.delete_at(first_index) if first_index
      end

      remaining.each do |child|
        next unless child.is_a?(Hash)

        lines.concat(render_block_node(node: child, depth: depth + 1))
      end

      lines
    end

    def render_list_item(item:, depth:, ordered:, number:)
      return [] unless item.is_a?(Hash)

      children = Array(item["content"])
      first_paragraph = children.find { |child| child.is_a?(Hash) && child["type"] == "paragraph" }

      first_text =
        if first_paragraph
          render_inline_nodes(Array(first_paragraph["content"]))
        else
          render_inline_nodes(children)
        end

      marker = ordered ? "#{number}." : "-"
      lines = [ "#{indent(depth)}#{marker} #{first_text}".rstrip ]

      remaining = children.dup
      if first_paragraph
        first_index = remaining.index(first_paragraph)
        remaining.delete_at(first_index) if first_index
      end

      remaining.each do |child|
        next unless child.is_a?(Hash)

        case child["type"]
        when "paragraph"
          text = render_inline_nodes(Array(child["content"]))
          lines << "#{indent(depth + 1)}#{text}" if text.present?
        when "bulletList", "orderedList", "taskList", "blockquote", "codeBlock"
          lines.concat(render_block_node(node: child, depth: depth + 1))
        end
      end

      lines
    end

    def render_blockquote(node:, depth:)
      child_lines = render_block_nodes(nodes: Array(node["content"]), depth: depth)
      child_lines.map do |line|
        stripped = line.to_s.strip
        stripped.blank? ? "#{indent(depth)}>" : "#{indent(depth)}> #{stripped}"
      end
    end

    def render_code_block(node:, depth:)
      lines = [ "#{indent(depth)}```" ]
      code = Array(node["content"]).filter_map { |child| child.is_a?(Hash) ? child["text"] : nil }.join
      code.split(/\r?\n/, -1).each do |line|
        lines << "#{indent(depth)}#{line}"
      end
      lines << "#{indent(depth)}```"
      lines
    end

    def render_inline_nodes(nodes)
      nodes.filter_map do |node|
        case node
        when Hash
          if node["type"] == "text"
            render_text_node(node)
          elsif node["type"] == "hardBreak"
            "\n"
          elsif node["content"].is_a?(Array)
            render_inline_nodes(node["content"])
          end
        end
      end.join
    end

    def render_text_node(node)
      text = node["text"].to_s
      return "" if text.blank?

      marks = Array(node["marks"])
      link_mark = marks.find { |mark| mark["type"] == "link" && mark.dig("attrs", "href").present? }
      text = "[#{text}](#{link_mark.dig('attrs', 'href')})" if link_mark

      marks.each do |mark|
        case mark["type"]
        when "strong", "bold"
          text = "**#{text}**"
        when "em", "italic"
          text = "*#{text}*"
        when "code"
          text = "`#{text}`"
        end
      end

      text
    end

    def extract_plain_text(node, collector = [])
      case node
      when Hash
        collector << node["text"] if node["text"].is_a?(String)
        node.each_value { |value| extract_plain_text(value, collector) }
      when Array
        node.each { |value| extract_plain_text(value, collector) }
      end

      collector.join(" ").squish
    end

    def indent(depth)
      "  " * depth
    end

    def normalize_lines(lines)
      compacted = []

      lines.each do |line|
        normalized = line.to_s.rstrip
        if normalized.empty?
          compacted << "" unless compacted.last == ""
        else
          compacted << normalized
        end
      end

      compacted.shift while compacted.first == ""
      compacted.pop while compacted.last == ""
      compacted.join("\n")
    end
  end
end
