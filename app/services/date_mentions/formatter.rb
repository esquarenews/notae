module DateMentions
  class Formatter
    TOKEN_REGEX = /(^|\s)@(date|today|tomorrow|yesterday|\d{4}-\d{2}-\d{2})(?=\b)/i

    class << self
      def replace_in_content_json(content_json:, preference:)
        transformed = deep_clone(content_json)
        replace_in_node!(transformed, preference: preference)
        transformed
      end

      def format(date:, preference:)
        date = date.to_date

        case preference.to_s
        when "full_date"
          "@#{date.strftime('%B %-d, %Y')}"
        when "short_date"
          "@#{date.strftime('%b %-d')}"
        when "month_day_year"
          "@#{date.strftime('%m/%d/%Y')}"
        when "day_month_year"
          "@#{date.strftime('%d/%m/%Y')}"
        when "year_month_day"
          "@#{date.strftime('%Y/%m/%d')}"
        else
          format_relative(date)
        end
      end

      private

      def deep_clone(content_json)
        return {} if content_json.blank?

        JSON.parse(JSON.generate(content_json))
      rescue JSON::ParserError, TypeError
        content_json
      end

      def replace_in_node!(node, preference:)
        case node
        when Hash
          if node["text"].is_a?(String)
            node["text"] = replace_in_text(node["text"], preference: preference)
          end
          node.each_value { |value| replace_in_node!(value, preference: preference) }
        when Array
          node.each { |child| replace_in_node!(child, preference: preference) }
        end
      end

      def replace_in_text(text, preference:)
        text.gsub(TOKEN_REGEX) do
          prefix = Regexp.last_match(1)
          token = Regexp.last_match(2)
          mention_date = parse_mention_date(token)

          "#{prefix}#{format(date: mention_date, preference: preference)}"
        end
      end

      def parse_mention_date(token)
        normalized = token.to_s.downcase
        today = Time.zone.today

        case normalized
        when "date", "today"
          today
        when "tomorrow"
          today + 1
        when "yesterday"
          today - 1
        else
          Date.iso8601(normalized)
        end
      rescue ArgumentError
        today
      end

      def format_relative(date)
        delta = date - Time.zone.today
        label = case delta
        when 0
          "Today"
        when 1
          "Tomorrow"
        when -1
          "Yesterday"
        else
          date.strftime("%b %-d, %Y")
        end

        "@#{label}"
      end
    end
  end
end
