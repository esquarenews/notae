module Notae
  class PdfFontFamily
    FAMILY_NAME = "Notae Sans".freeze
    FALLBACK_FAMILY = "Helvetica".freeze
    FONT_DIRECTORY = Rails.root.join("app/assets/fonts/notae_sans/static").freeze
    FONT_FILES = {
      normal: FONT_DIRECTORY.join("NotaeSans-Regular.ttf"),
      bold: FONT_DIRECTORY.join("NotaeSans-Bold.ttf"),
      italic: FONT_DIRECTORY.join("NotaeSans-Italic.ttf"),
      bold_italic: FONT_DIRECTORY.join("NotaeSans-BoldItalic.ttf")
    }.freeze

    class << self
      def register(pdf)
        return FALLBACK_FAMILY unless available?

        pdf.font_families.update(
          FAMILY_NAME => FONT_FILES.transform_values(&:to_s)
        )
        FAMILY_NAME
      end

      def available?
        FONT_FILES.values.all?(&:file?)
      end
    end
  end
end
