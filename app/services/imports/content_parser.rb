require "stringio"

module Imports
  class ContentParser
    Document = Struct.new(:title, :blocks, :target_type, :table_rows, keyword_init: true)
    ParseResult = Struct.new(:documents, :skipped_files, keyword_init: true)
    UnsupportedFormatError = Class.new(StandardError)
    TARGET_PAGE = "page".freeze
    TARGET_DATABASE = "database".freeze

    SUPPORTED_EXTENSIONS = %w[.txt .md .markdown .html .htm .csv .pdf .docx .zip .epub].freeze
    DOCX_NS = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

    class << self
      def parse(filename:, io:)
        new.parse(filename: filename, io: io)
      end
    end

    def parse(filename:, io:)
      data = read_binary(io)
      parse_binary(filename: filename.to_s, data: data)
    end

    private

    def parse_binary(filename:, data:)
      extension = File.extname(filename.to_s).downcase
      raise UnsupportedFormatError, "Unsupported format: #{filename}" unless SUPPORTED_EXTENSIONS.include?(extension)

      documents, skipped_files =
        case extension
        when ".txt"
          [ [ Document.new(title: title_from_filename(filename), blocks: parse_plain_text(data), target_type: TARGET_PAGE) ], [] ]
        when ".md", ".markdown"
          [ [ Document.new(title: title_from_filename(filename), blocks: parse_markdown(data), target_type: TARGET_PAGE) ], [] ]
        when ".html", ".htm"
          [ [ Document.new(title: title_from_filename(filename), blocks: parse_html(data), target_type: TARGET_PAGE) ], [] ]
        when ".csv"
          [ [ parse_csv_document(filename: filename, data: data) ], [] ]
        when ".pdf"
          [ [ Document.new(title: title_from_filename(filename), blocks: parse_pdf(data), target_type: TARGET_PAGE) ], [] ]
        when ".docx"
          [ [ Document.new(title: title_from_filename(filename), blocks: parse_docx(data), target_type: TARGET_PAGE) ], [] ]
        when ".epub"
          parse_epub(filename: filename, data: data)
        when ".zip"
          parse_zip(data: data)
        else
          [ [], [ filename ] ]
        end

      ParseResult.new(documents: documents, skipped_files: skipped_files)
    end

    def parse_plain_text(data)
      paragraphs = text_from_data(data).split(/\n{2,}/).map { |paragraph| paragraph.gsub(/\s+/, " ").strip }.reject(&:blank?)
      blocks = paragraphs.map { |paragraph| paragraph_block(paragraph) }
      blocks.presence || [ paragraph_block("Imported file") ]
    end

    def parse_markdown(data)
      lines = text_from_data(data).gsub("\r\n", "\n").split("\n")
      blocks = []
      paragraph_lines = []
      list_type = nil
      list_items = []
      in_code_block = false
      code_lines = []

      flush_paragraph = lambda do
        if paragraph_lines.any?
          blocks << paragraph_block(paragraph_lines.join(" "))
          paragraph_lines.clear
        end
      end

      flush_list = lambda do
        if list_type.present? && list_items.any?
          blocks << list_block(list_type: list_type, items: list_items)
        end
        list_type = nil
        list_items = []
      end

      lines.each do |line|
        stripped = line.strip
        if in_code_block
          if stripped.start_with?("```")
            blocks << code_block(code_lines.join("\n"))
            in_code_block = false
            code_lines = []
          else
            code_lines << line
          end
          next
        end

        if stripped.start_with?("```")
          flush_paragraph.call
          flush_list.call
          in_code_block = true
          next
        end

        if stripped.blank?
          flush_paragraph.call
          flush_list.call
          next
        end

        if (heading_match = stripped.match(/\A(\#{1,3})\s+(.+)\z/))
          flush_paragraph.call
          flush_list.call
          level = heading_match[1].length
          blocks << heading_block(level: level, text: heading_match[2])
          next
        end

        if (todo_match = stripped.match(/\A[-*+]\s+\[( |x|X)\]\s+(.+)\z/))
          flush_paragraph.call
          if list_type != "todo_list"
            flush_list.call
            list_type = "todo_list"
          end
          list_items << { text: todo_match[2], checked: todo_match[1].casecmp("x").zero? }
          next
        end

        if (bullet_match = stripped.match(/\A[-*+]\s+(.+)\z/))
          flush_paragraph.call
          if list_type != "bullet_list"
            flush_list.call
            list_type = "bullet_list"
          end
          list_items << { text: bullet_match[1] }
          next
        end

        if (ordered_match = stripped.match(/\A\d+\.\s+(.+)\z/))
          flush_paragraph.call
          if list_type != "ordered_list"
            flush_list.call
            list_type = "ordered_list"
          end
          list_items << { text: ordered_match[1] }
          next
        end

        if (quote_match = stripped.match(/\A>\s?(.+)\z/))
          flush_paragraph.call
          flush_list.call
          blocks << quote_block(quote_match[1])
          next
        end

        paragraph_lines << stripped
      end

      if in_code_block && code_lines.any?
        blocks << code_block(code_lines.join("\n"))
      end

      flush_paragraph.call
      flush_list.call
      blocks.presence || [ paragraph_block("Imported file") ]
    end

    def parse_html(data)
      unless ensure_nokogiri_loaded
        return [ paragraph_block("HTML import is unavailable because the nokogiri dependency is missing in this environment.") ]
      end

      fragment = Nokogiri::HTML.fragment(text_from_data(data))
      blocks = blocks_from_html_nodes(fragment.children)
      blocks.presence || [ paragraph_block(fragment.text.to_s.strip.presence || "Imported file") ]
    end

    def parse_csv(data)
      raw_text = text_from_data(data)
      table = parse_csv_rows(raw_text)
      lines = table.map { |row| row.map { |value| value.to_s.strip }.join(" | ") }
      table_text = lines.join("\n").strip
      [
        heading_block(level: 2, text: "Imported table"),
        code_block(table_text.presence || raw_text.strip.presence || "No rows")
      ]
    end

    def parse_csv_document(filename:, data:)
      raw_text = text_from_data(data)
      table_rows = parse_csv_rows(raw_text)

      Document.new(
        title: title_from_filename(filename),
        blocks: parse_csv(data),
        target_type: TARGET_DATABASE,
        table_rows: table_rows
      )
    end

    def parse_csv_rows(raw_text)
      begin
        require "csv"
        CSV.parse(raw_text)
      rescue LoadError
        raw_text.split(/\r?\n/).map { |line| line.split(",") }
      end
    end

    def parse_pdf(data)
      unless ensure_pdf_reader_loaded
        return [ paragraph_block("PDF import is unavailable because the pdf-reader dependency is missing in this environment.") ]
      end

      reader = PDF::Reader.new(StringIO.new(data))
      blocks = []
      multi_page = reader.pages.size > 1
      reader.pages.each_with_index do |page, index|
        page_text = page.text.to_s
        next if page_text.blank?

        blocks << heading_block(level: 3, text: "Page #{index + 1}") if multi_page
        page_text.split(/\n{2,}/).each do |paragraph|
          compact = paragraph.gsub(/\s+/, " ").strip
          next if compact.blank?

          blocks << paragraph_block(compact)
        end
      end
      blocks.presence || [ paragraph_block("Imported PDF") ]
    rescue StandardError
      [ paragraph_block("PDF import could not preserve full formatting. Raw extraction unavailable.") ]
    end

    def parse_docx(data)
      unless ensure_zip_loaded
        return [ paragraph_block("DOCX import is unavailable because the rubyzip dependency is missing in this environment.") ]
      end
      unless ensure_nokogiri_loaded
        return [ paragraph_block("DOCX import is unavailable because the nokogiri dependency is missing in this environment.") ]
      end

      blocks = []
      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        entry = zip.find_entry("word/document.xml")
        return [ paragraph_block("DOCX file did not contain readable document content.") ] unless entry

        xml = Nokogiri::XML(entry.get_input_stream.read)
        xml.xpath("//w:body/w:p", DOCX_NS).each do |paragraph_node|
          inline_nodes = inline_nodes_from_docx_paragraph(paragraph_node)
          plain_text = inline_nodes.map { |node| node["text"] }.join.strip
          next if plain_text.blank?

          heading_level = heading_level_from_docx_paragraph(paragraph_node)
          if heading_level
            blocks << heading_block(level: heading_level, text: plain_text)
          elsif paragraph_node.at_xpath("./w:pPr/w:numPr", DOCX_NS)
            blocks << list_block(list_type: "bullet_list", items: [ { text: plain_text } ])
          else
            blocks << paragraph_block(plain_text, inline_nodes: inline_nodes)
          end
        end
      end
      blocks.presence || [ paragraph_block("Imported DOCX") ]
    rescue StandardError
      [ paragraph_block("DOCX import failed to preserve formatting for this file.") ]
    end

    def parse_epub(filename:, data:)
      unless ensure_zip_loaded
        return [ [ Document.new(title: title_from_filename(filename), blocks: [ paragraph_block("EPUB import is unavailable because the rubyzip dependency is missing in this environment.") ], target_type: TARGET_PAGE) ], [] ]
      end
      unless ensure_nokogiri_loaded
        return [ [ Document.new(title: title_from_filename(filename), blocks: [ paragraph_block("EPUB import is unavailable because the nokogiri dependency is missing in this environment.") ], target_type: TARGET_PAGE) ], [] ]
      end

      documents = []
      skipped = []
      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        entries = zip.entries.select do |entry|
          next false if entry.name_is_directory?

          ext = File.extname(entry.name).downcase
          [ ".html", ".htm", ".xhtml" ].include?(ext)
        end

        entries.sort_by(&:name).each do |entry|
          html = entry.get_input_stream.read
          doc = Nokogiri::HTML(html)
          title = doc.at("title")&.text.to_s.strip.presence || title_from_filename(entry.name)
          blocks = blocks_from_html_nodes((doc.at("body") || doc).children)
          documents << Document.new(title: "#{title_from_filename(filename)} — #{title}", blocks: blocks.presence || [ paragraph_block("Imported section") ], target_type: TARGET_PAGE)
        end
      end
      [ documents, skipped ]
    rescue StandardError
      [ [ Document.new(title: title_from_filename(filename), blocks: [ paragraph_block("EPUB import failed for this file.") ], target_type: TARGET_PAGE) ], [] ]
    end

    def parse_zip(data:)
      unless ensure_zip_loaded
        return [ [], [ "ZIP import is unavailable because the rubyzip dependency is missing in this environment." ] ]
      end

      documents = []
      skipped = []
      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        zip.entries.each do |entry|
          next if entry.name_is_directory?

          ext = File.extname(entry.name).downcase
          unless SUPPORTED_EXTENSIONS.include?(ext)
            skipped << entry.name
            next
          end

          next if ext == ".zip"

          entry_result = parse_binary(filename: entry.name, data: entry.get_input_stream.read)
          documents.concat(entry_result.documents.map do |doc|
            Document.new(
              title: "#{title_from_filename(entry.name)}#{doc.title.present? ? " — #{doc.title}" : ""}",
              blocks: doc.blocks,
              target_type: doc.target_type,
              table_rows: doc.table_rows
            )
          end)
          skipped.concat(entry_result.skipped_files)
        rescue UnsupportedFormatError
          skipped << entry.name
        end
      end
      [ documents, skipped ]
    rescue StandardError
      [ [], [ "ZIP archive could not be read" ] ]
    end

    def blocks_from_html_nodes(nodes)
      blocks = []
      nodes.each do |node|
        case node
        when Nokogiri::XML::Text
          compact_text = node.text.to_s.gsub(/\s+/, " ").strip
          blocks << paragraph_block(compact_text) if compact_text.present?
        when Nokogiri::XML::Element
          name = node.name.downcase
          case name
          when "h1"
            blocks << heading_block(level: 1, text: node.text.to_s.strip)
          when "h2"
            blocks << heading_block(level: 2, text: node.text.to_s.strip)
          when "h3"
            blocks << heading_block(level: 3, text: node.text.to_s.strip)
          when "p"
            inline_nodes = inline_nodes_from_html(node.children)
            blocks << paragraph_block(node.text.to_s.strip, inline_nodes: inline_nodes)
          when "ul"
            items = node.css("> li").map { |item| { text: item.text.to_s.gsub(/\s+/, " ").strip } }.reject { |item| item[:text].blank? }
            blocks << list_block(list_type: "bullet_list", items: items) if items.any?
          when "ol"
            items = node.css("> li").map { |item| { text: item.text.to_s.gsub(/\s+/, " ").strip } }.reject { |item| item[:text].blank? }
            blocks << list_block(list_type: "ordered_list", items: items) if items.any?
          when "pre"
            blocks << code_block(node.text.to_s)
          when "blockquote"
            blocks << quote_block(node.text.to_s.gsub(/\s+/, " ").strip)
          when "div", "section", "article", "main", "body"
            blocks.concat(blocks_from_html_nodes(node.children))
          end
        end
      end
      blocks
    end

    def heading_level_from_docx_paragraph(paragraph_node)
      style_value = paragraph_node.at_xpath("./w:pPr/w:pStyle", DOCX_NS)&.[]("w:val")
      return nil if style_value.blank?

      match = style_value.match(/heading([1-3])/i)
      match ? match[1].to_i : nil
    end

    def inline_nodes_from_docx_paragraph(paragraph_node)
      nodes = []
      paragraph_node.xpath("./w:r", DOCX_NS).each do |run|
        text = run.xpath(".//w:t", DOCX_NS).map(&:text).join
        text += "\n" if run.xpath(".//w:br", DOCX_NS).any?
        next if text.blank?

        marks = []
        marks << { "type" => "bold" } if run.at_xpath("./w:rPr/w:b", DOCX_NS)
        marks << { "type" => "italic" } if run.at_xpath("./w:rPr/w:i", DOCX_NS)
        marks << { "type" => "code" } if run.at_xpath("./w:rPr/w:rStyle[@w:val='Code']", DOCX_NS)

        text_node = { "type" => "text", "text" => text }
        text_node["marks"] = marks if marks.any?
        nodes << text_node
      end

      if nodes.empty?
        fallback = paragraph_node.text.to_s.gsub(/\s+/, " ").strip
        nodes << { "type" => "text", "text" => fallback } if fallback.present?
      end

      nodes
    end

    def inline_nodes_from_html(nodes, marks = [])
      output = []
      nodes.each do |node|
        case node
        when Nokogiri::XML::Text
          text = node.text.to_s.gsub(/\s+/, " ")
          next if text.blank?

          text_node = { "type" => "text", "text" => text }
          text_node["marks"] = marks if marks.any?
          output << text_node
        when Nokogiri::XML::Element
          next_marks = marks.dup
          case node.name.downcase
          when "strong", "b"
            next_marks << { "type" => "bold" }
          when "em", "i"
            next_marks << { "type" => "italic" }
          when "code"
            next_marks << { "type" => "code" }
          when "a"
            href = node["href"].to_s.strip
            if href.present?
              next_marks << { "type" => "link", "attrs" => { "href" => href } }
            end
          when "br"
            output << { "type" => "text", "text" => "\n" }
            next
          end
          output.concat(inline_nodes_from_html(node.children, next_marks))
        end
      end
      compact_inline_nodes(output)
    end

    def compact_inline_nodes(nodes)
      cleaned = nodes.map do |node|
        text = node["text"].to_s
        next if text.blank?

        { "type" => "text", "text" => text, "marks" => node["marks"] }.compact
      end.compact
      return cleaned if cleaned.empty?

      cleaned.first["text"] = cleaned.first["text"].sub(/\A\s+/, "")
      cleaned.last["text"] = cleaned.last["text"].sub(/\s+\z/, "")
      cleaned.reject { |node| node["text"].blank? }
    end

    def parse_inline_markdown(text)
      remaining = text.to_s
      output = []
      while remaining.present?
        if (match = remaining.match(/\A\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/))
          append_inline_text(output, match[1], marks: [ { "type" => "link", "attrs" => { "href" => match[2] } } ])
          remaining = remaining[match[0].length..]
          next
        end

        if (match = remaining.match(/\A\*\*([^*]+)\*\*/))
          append_inline_text(output, match[1], marks: [ { "type" => "bold" } ])
          remaining = remaining[match[0].length..]
          next
        end

        if (match = remaining.match(/\A\*([^*]+)\*/))
          append_inline_text(output, match[1], marks: [ { "type" => "italic" } ])
          remaining = remaining[match[0].length..]
          next
        end

        if (match = remaining.match(/\A`([^`]+)`/))
          append_inline_text(output, match[1], marks: [ { "type" => "code" } ])
          remaining = remaining[match[0].length..]
          next
        end

        next_special = remaining.index(/(\[|\*\*|\*|`)/)
        chunk = next_special ? remaining[0...next_special] : remaining
        append_inline_text(output, chunk)
        remaining = next_special ? remaining[next_special..] : ""
      end
      compact_inline_nodes(output)
    end

    def append_inline_text(target, text, marks: [])
      compact = text.to_s
      return if compact.blank?

      node = { "type" => "text", "text" => compact }
      node["marks"] = marks if marks.any?
      target << node
    end

    def paragraph_block(text, inline_nodes: nil)
      content = inline_nodes.presence || parse_inline_markdown(text)
      paragraph = { "type" => "paragraph" }
      paragraph["content"] = content if content.any?
      build_block(block_type: "paragraph", node: paragraph)
    end

    def heading_block(level:, text:)
      heading_level = level.to_i.clamp(1, 3)
      content = parse_inline_markdown(text)
      heading = { "type" => "heading", "attrs" => { "level" => heading_level } }
      heading["content"] = content if content.any?
      build_block(block_type: "heading_#{heading_level}", node: heading)
    end

    def quote_block(text)
      content = parse_inline_markdown(text)
      paragraph = { "type" => "paragraph" }
      paragraph["content"] = content if content.any?
      build_block(block_type: "blockquote", node: { "type" => "blockquote", "content" => [ paragraph ] })
    end

    def code_block(text)
      code_node = { "type" => "codeBlock" }
      text_content = text.to_s
      if text_content.present?
        code_node["content"] = [ { "type" => "text", "text" => text_content } ]
      end
      build_block(block_type: "code_block", node: code_node)
    end

    def list_block(list_type:, items:)
      return paragraph_block("Imported list") if items.blank?

      list_node =
        case list_type
        when "ordered_list"
          {
            "type" => "orderedList",
            "content" => items.map do |item|
              {
                "type" => "listItem",
                "content" => [ paragraph_node_for_list_item(item[:text]) ]
              }
            end
          }
        when "todo_list"
          {
            "type" => "taskList",
            "content" => items.map do |item|
              {
                "type" => "taskItem",
                "attrs" => { "checked" => item[:checked] == true },
                "content" => [ paragraph_node_for_list_item(item[:text]) ]
              }
            end
          }
        else
          {
            "type" => "bulletList",
            "content" => items.map do |item|
              {
                "type" => "listItem",
                "content" => [ paragraph_node_for_list_item(item[:text]) ]
              }
            end
          }
        end

      build_block(block_type: list_type, node: list_node)
    end

    def paragraph_node_for_list_item(text)
      content = parse_inline_markdown(text.to_s)
      node = { "type" => "paragraph" }
      node["content"] = content if content.any?
      node
    end

    def build_block(block_type:, node:)
      {
        block_type: block_type,
        content_json: {
          "type" => "doc",
          "content" => [ node ]
        }
      }
    end

    def title_from_filename(filename)
      File.basename(filename.to_s, File.extname(filename.to_s)).tr("_-", " ").squeeze(" ").strip.presence || "Imported page"
    end

    def read_binary(io)
      io.rewind if io.respond_to?(:rewind)
      data = io.read
      data = data.read if data.respond_to?(:read)
      data.to_s.b
    end

    def text_from_data(data)
      data.to_s.force_encoding("UTF-8")
      data.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      data.to_s.force_encoding("UTF-8").scrub
    end

    def ensure_nokogiri_loaded
      require "nokogiri"
      true
    rescue LoadError
      false
    end

    def ensure_pdf_reader_loaded
      return true if defined?(PDF::Reader)

      errors = []
      errors << require_attempt("pdf/reader")
      return true if defined?(PDF::Reader)

      errors << require_attempt("pdf-reader")
      return true if defined?(PDF::Reader)

      if activate_pdf_reader_load_path
        errors << require_attempt("pdf/reader")
        return true if defined?(PDF::Reader)
      end

      log_missing_dependency("pdf-reader", errors)
      false
    end

    def ensure_zip_loaded
      require "zip"
      true
    rescue LoadError
      false
    end

    def log_missing_dependency(name, *errors)
      return unless defined?(Rails) && Rails.logger

      details = errors.flatten.compact.map(&:message).uniq.join(" | ")
      Rails.logger.warn("[imports] missing dependency #{name}: #{details}")
    end

    def require_attempt(path)
      require path
      nil
    rescue LoadError => error
      error
    end

    def activate_pdf_reader_load_path
      spec = Gem.loaded_specs["pdf-reader"] || Gem::Specification.find_all_by_name("pdf-reader").first
      return false unless spec

      spec.full_require_paths.each do |path|
        $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
      end
      true
    rescue StandardError => error
      log_missing_dependency("pdf-reader-load-path", error)
      false
    end
  end
end
