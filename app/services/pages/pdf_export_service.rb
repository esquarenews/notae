module Pages
  class PdfExportService
    Result = Struct.new(:pdf, keyword_init: true)
    Element = Struct.new(:text, :font, :size, :leading, :indent, keyword_init: true)

    PAGE_WIDTH = 612.0
    PAGE_HEIGHT = 792.0
    PAGE_MARGIN = 54.0
    BODY_FONT = "F1".freeze
    HEADING_FONT = "F2".freeze
    BODY_SIZE = 11.0
    BODY_LEADING = 16.0
    SPACER_LEADING = 8.0
    DEFAULT_INDENT = 0.0

    class << self
      def call(page:)
        new(page: page).call
      end
    end

    def initialize(page:)
      @page = page
    end

    def call
      markdown = Pages::MarkdownExportService.call(page: page).markdown
      Result.new(pdf: render_pdf(build_elements(markdown)))
    end

    private

    attr_reader :page

    def build_elements(markdown)
      elements = []
      append_wrapped_text(
        elements: elements,
        text: sanitize_text(page.title),
        font: HEADING_FONT,
        size: 22.0,
        leading: 30.0
      )
      elements << Element.new(text: nil, leading: 12.0, indent: DEFAULT_INDENT)

      body_lines(markdown).each do |line|
        if line.blank?
          elements << Element.new(text: nil, leading: SPACER_LEADING, indent: DEFAULT_INDENT)
          next
        end

        append_line(elements: elements, line: line)
      end

      elements
    end

    def body_lines(markdown)
      lines = markdown.to_s.lines.map { |line| line.chomp }
      title_line = "# #{page.title}"
      return lines unless lines.first == title_line

      lines.drop(1).drop_while(&:blank?)
    end

    def append_line(elements:, line:)
      indentation = line[/\A\s*/].to_s.length * 4.0
      text = sanitize_text(line.lstrip)
      return if text.blank?

      heading_match = text.match(/\A(#+)\s+(.*)\z/)

      if heading_match
        level = heading_match[1].length.clamp(1, 6)
        append_wrapped_text(
          elements: elements,
          text: heading_match[2],
          font: HEADING_FONT,
          size: heading_size(level),
          leading: heading_leading(level),
          indent: indentation
        )
      else
        append_wrapped_text(
          elements: elements,
          text: text,
          font: BODY_FONT,
          size: BODY_SIZE,
          leading: BODY_LEADING,
          indent: indentation
        )
      end
    end

    def append_wrapped_text(elements:, text:, font:, size:, leading:, indent: DEFAULT_INDENT)
      wrapped_lines(text: text, size: size, indent: indent).each do |wrapped_line|
        elements << Element.new(text: wrapped_line, font: font, size: size, leading: leading, indent: indent)
      end
    end

    def wrapped_lines(text:, size:, indent:)
      available_width = PAGE_WIDTH - (PAGE_MARGIN * 2) - indent
      max_chars = [ (available_width / (size * 0.55)).floor, 12 ].max
      words = text.split(/\s+/)
      return [ text ] if words.empty?

      lines = []
      current = +""

      words.each do |word|
        if current.empty?
          append_word_or_chunks(lines, word, max_chars) { |value| current = value }
          next
        end

        candidate = "#{current} #{word}"
        if candidate.length <= max_chars
          current = candidate
        else
          lines << current
          append_word_or_chunks(lines, word, max_chars) { |value| current = value }
        end
      end

      lines << current unless current.empty?
      lines
    end

    def append_word_or_chunks(lines, word, max_chars)
      if word.length <= max_chars
        yield word
        return
      end

      chunks = word.scan(/.{1,#{max_chars}}/)
      lines.concat(chunks[0...-1])
      yield chunks.last.to_s
    end

    def heading_size(level)
      case level
      when 1 then 18.0
      when 2 then 16.0
      when 3 then 14.0
      when 4 then 13.0
      when 5 then 12.0
      else 11.0
      end
    end

    def heading_leading(level)
      heading_size(level) + 7.0
    end

    def sanitize_text(text)
      normalized = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      I18n.transliterate(normalized).gsub(/[[:cntrl:]&&[^\n\t]]/, "").squish
    end

    def render_pdf(elements)
      page_streams = build_page_streams(elements)
      objects = {
        1 => "<< /Type /Catalog /Pages 2 0 R >>",
        3 => "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        4 => "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"
      }

      next_object_id = 5
      page_ids = []

      page_streams.each do |stream|
        page_id = next_object_id
        content_id = next_object_id + 1
        next_object_id += 2
        page_ids << page_id

        objects[page_id] = <<~PDF.squish
          << /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}]
             /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >>
             /Contents #{content_id} 0 R >>
        PDF
        objects[content_id] = stream_object(stream)
      end

      objects[2] = "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{page_ids.length} >>"
      assemble_pdf(objects)
    end

    def build_page_streams(elements)
      pages = [ [] ]
      cursor_y = PAGE_HEIGHT - PAGE_MARGIN

      elements.each do |element|
        leading = element.leading || BODY_LEADING
        if cursor_y - leading < PAGE_MARGIN
          pages << []
          cursor_y = PAGE_HEIGHT - PAGE_MARGIN
        end

        if element.text.present?
          pages.last << line_command(element, cursor_y)
        end

        cursor_y -= leading
      end

      pages.map do |commands|
        if commands.empty?
          "BT\n/#{BODY_FONT} #{BODY_SIZE} Tf\n1 0 0 1 #{PAGE_MARGIN} #{PAGE_HEIGHT - PAGE_MARGIN} Tm\n() Tj\nET"
        else
          "BT\n#{commands.join("\n")}\nET"
        end
      end
    end

    def line_command(element, y_position)
      x_position = PAGE_MARGIN + (element.indent || DEFAULT_INDENT)
      escaped_text = escape_pdf_text(element.text)
      <<~PDF.strip
        /#{element.font} #{format('%.2f', element.size)} Tf
        1 0 0 1 #{format('%.2f', x_position)} #{format('%.2f', y_position)} Tm
        (#{escaped_text}) Tj
      PDF
    end

    def escape_pdf_text(text)
      text.to_s.gsub(/([\\()])/, '\\\\\1')
    end

    def stream_object(content)
      bytes = content.dup.force_encoding(Encoding::BINARY)
      "<< /Length #{bytes.bytesize} >>\nstream\n#{bytes}\nendstream"
    end

    def assemble_pdf(objects)
      pdf = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"
      pdf.force_encoding(Encoding::BINARY)
      offsets = {}
      object_ids = objects.keys.sort

      object_ids.each do |object_id|
        offsets[object_id] = pdf.bytesize
        pdf << "#{object_id} 0 obj\n#{objects[object_id]}\nendobj\n"
      end

      xref_offset = pdf.bytesize
      max_object_id = object_ids.max
      pdf << "xref\n0 #{max_object_id + 1}\n"
      pdf << "0000000000 65535 f \n"

      (1..max_object_id).each do |object_id|
        if offsets.key?(object_id)
          pdf << format("%010d 00000 n \n", offsets[object_id])
        else
          pdf << "0000000000 00000 f \n"
        end
      end

      pdf << "trailer\n<< /Size #{max_object_id + 1} /Root 1 0 R >>\n"
      pdf << "startxref\n#{xref_offset}\n%%EOF\n"
      pdf
    end
  end
end
