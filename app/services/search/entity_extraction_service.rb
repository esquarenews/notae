module Search
  class EntityExtractionService
    EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
    URL_PATTERN = %r{https?://[^\s<>()]+}i
    DATE_PATTERN = /\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}[\/\-]\d{1,2}(?:[\/\-]\d{2,4})?)\b/
    PROPER_NOUN_PATTERN = /\b(?:[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b/

    def self.call(text:, limit: 12)
      new(text: text, limit: limit).call
    end

    def initialize(text:, limit: 12)
      @text = text.to_s
      @limit = limit.to_i
    end

    def call
      {
        "emails" => extract(EMAIL_PATTERN),
        "urls" => extract(URL_PATTERN),
        "dates" => extract(DATE_PATTERN),
        "names" => extract(PROPER_NOUN_PATTERN, reject: %w[Summary Decisions Calendar Page Row])
      }.transform_values { |values| values.first(limit) }
    end

    private

    attr_reader :text, :limit

    def extract(pattern, reject: [])
      text.scan(pattern).flatten.map { |value| value.to_s.strip }.reject(&:blank?).uniq.reject do |value|
        reject.include?(value)
      end
    end
  end
end
