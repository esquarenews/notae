require "prawn"

module Pages
  class PdfExportService
    Result = Struct.new(:pdf, keyword_init: true)

    PAGE_WIDTH = 612.0
    PAGE_HEIGHT = 792.0
    PAGE_MARGIN = 54.0
    BODY_SIZE = 11.0
    BODY_LEADING = 16.0
    SPACER_LEADING = 8.0
    TITLE_SIZE = 22.0
    TITLE_LEADING = 30.0
    TITLE_GAP = 12.0
    DEFAULT_INDENT = 0.0
    MIN_TEXT_WIDTH = 72.0

    class << self
      def call(page:)
        new(page:).call
      end
    end

    def initialize(page:)
      @page = page
    end

    def call
      markdown = Pages::MarkdownExportService.call(page:).markdown
      pdf = build_document
      @font_family = Notae::PdfFontFamily.register(pdf)
      pdf.font(font_family)

      render_title(pdf)
      render_body(pdf, markdown)

      Result.new(pdf: pdf.render)
    end

    private

    attr_reader :page, :font_family

    def build_document
      Prawn::Document.new(
        page_size: [ PAGE_WIDTH, PAGE_HEIGHT ],
        margin: PAGE_MARGIN,
        info: { Title: normalize_text(page.title).presence || "Untitled Nota" }
      )
    end

    def render_title(pdf)
      with_font(pdf, style: :bold) do
        pdf.text(
          renderable_text(page.title),
          size: TITLE_SIZE,
          leading: TITLE_LEADING - TITLE_SIZE
        )
      end
      move_down_or_start_page(pdf, TITLE_GAP)
    end

    def render_body(pdf, markdown)
      body_lines(markdown).each do |line|
        if line.blank?
          move_down_or_start_page(pdf, SPACER_LEADING)
        else
          render_line(pdf, line)
        end
      end
    end

    def body_lines(markdown)
      lines = markdown.to_s.lines.map { |line| line.chomp }
      title_line = "# #{page.title}"
      return lines unless lines.first == title_line

      lines.drop(1).drop_while(&:blank?)
    end

    def render_line(pdf, line)
      indentation = indentation_for(pdf, line)
      text = renderable_text(line.lstrip)
      return if text.blank?

      heading_match = text.match(/\A(#+)\s+(.*)\z/)

      pdf.indent(indentation) do
        if heading_match
          render_heading(pdf, heading_match)
        else
          with_font(pdf, style: :normal) do
            pdf.text(text, size: BODY_SIZE, leading: BODY_LEADING - BODY_SIZE)
          end
        end
      end
    end

    def render_heading(pdf, heading_match)
      level = heading_match[1].length.clamp(1, 6)
      size = heading_size(level)

      with_font(pdf, style: :bold) do
        pdf.text(
          heading_match[2],
          size:,
          leading: heading_leading(level) - size
        )
      end
    end

    def indentation_for(pdf, line)
      requested_indent = line[/\A\s*/].to_s.length * 4.0
      maximum_indent = [ pdf.bounds.width - MIN_TEXT_WIDTH, DEFAULT_INDENT ].max
      requested_indent.clamp(DEFAULT_INDENT, maximum_indent)
    end

    def with_font(pdf, style:)
      pdf.font(font_family, style:) { yield }
    end

    def move_down_or_start_page(pdf, distance)
      if pdf.cursor >= distance
        pdf.move_down(distance)
      else
        pdf.start_new_page
      end
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

    def renderable_text(text)
      normalized = normalize_text(text)
      return normalized if font_family == Notae::PdfFontFamily::FAMILY_NAME

      I18n.transliterate(normalized)
          .encode(Encoding::Windows_1252, invalid: :replace, undef: :replace, replace: "?")
          .encode(Encoding::UTF_8)
    end

    def normalize_text(text)
      text.to_s
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
          .gsub(/[[:cntrl:]&&[^\n\t]]/, "")
          .squish
    end
  end
end
