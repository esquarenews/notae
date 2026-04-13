require "cgi"
require "set"

module Pages
  class MarkdownExportService
    Result = Struct.new(:markdown, :attachments, keyword_init: true)
    Attachment = Struct.new(:block_id, :blob, :filename, :relative_path, keyword_init: true)

    class << self
      def call(page:)
        new(page: page).call
      end
    end

    def initialize(page:)
      @page = page
      @blocks = page.blocks.active.order(:position, :created_at).includes(asset_attachment: :blob).to_a
      @blocks_by_parent = @blocks.group_by(&:parent_block_id)
      @attachments = []
      @attachment_paths = Set.new
    end

    def call
      lines = [ "# #{page.title}", "" ]
      append_block_tree(lines: lines, parent_id: nil, depth: 0)

      if attachments.any?
        lines << "" unless lines.last == ""
        lines << "## Attachments"
        attachments.each do |attachment|
          lines << "- [#{attachment.filename}](#{attachment.relative_path})"
        end
      end

      Result.new(markdown: normalize_lines(lines), attachments: attachments)
    end

    private

    attr_reader :page, :blocks_by_parent, :attachments, :attachment_paths

    def append_block_tree(lines:, parent_id:, depth:)
      blocks_by_parent.fetch(parent_id, []).each do |block|
        block_lines = markdown_lines_for_block(block: block, depth: depth)
        if block_lines.any?
          lines.concat(block_lines)
          lines << ""
        end

        append_block_tree(lines: lines, parent_id: block.id, depth: depth + 1)
      end
    end

    def markdown_lines_for_block(block:, depth:)
      if media_block?(block)
        attachment = register_attachment(block)
        return [] if attachment.blank?

        return [ "#{indent(depth)}- Attachment: [#{attachment.filename}](#{attachment.relative_path})" ]
      end

      if block.block_type.to_s == "embed"
        return [] if block.embed_url.blank?

        return [ "#{indent(depth)}[Embedded content](#{block.embed_url})" ]
      end

      if block.block_type.to_s == "gantt_embed"
        return [] if block.gantt_database_id.blank?

        return [ "#{indent(depth)}[Embedded Gantt chart](#{gantt_embed_path_for(block)})" ]
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

    def gantt_embed_path_for(block)
      workspace_slug = block.gantt_workspace_slug.presence || block.workspace&.slug
      path = "/w/#{workspace_slug}/databases/#{block.gantt_database_id}/gantt_embed"
      view_id = block.gantt_view_id.presence
      view_id.present? ? "#{path}?view_id=#{CGI.escape(view_id)}" : path
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
        when "bulletList", "orderedList"
          lines.concat(render_block_node(node: child, depth: depth + 1))
        end
      end

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

    def register_attachment(block)
      return nil unless block.asset.attached?

      existing = attachments.find { |attachment| attachment.block_id == block.id }
      return existing if existing

      filename = block.asset.filename.to_s
      path = unique_attachment_path(block_id: block.id, filename: filename)
      attachment = Attachment.new(
        block_id: block.id,
        blob: block.asset.blob,
        filename: filename,
        relative_path: path
      )
      attachments << attachment
      attachment
    end

    def unique_attachment_path(block_id:, filename:)
      sanitized = filename.gsub(/[^A-Za-z0-9.\-_]/, "_")
      sanitized = "file" if sanitized.blank?

      candidate = "attachments/#{block_id}-#{sanitized}"
      suffix = 2

      while attachment_paths.include?(candidate)
        candidate = "attachments/#{block_id}-#{suffix}-#{sanitized}"
        suffix += 1
      end

      attachment_paths << candidate
      candidate
    end

    def media_block?(block)
      %w[image file].include?(block.block_type.to_s)
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
