module Search
  class TextChunker
    DEFAULT_TARGET_WORDS = 180
    DEFAULT_OVERLAP_WORDS = 30

    def self.call(text, target_words: DEFAULT_TARGET_WORDS, overlap_words: DEFAULT_OVERLAP_WORDS)
      normalized = text.to_s.squish
      return [] if normalized.blank?

      words = normalized.split(/\s+/)
      return [] if words.empty?

      chunks = []
      start_index = 0
      step = [ target_words - overlap_words, 1 ].max

      while start_index < words.length
        slice = words[start_index, target_words]
        break if slice.blank?

        chunks << slice.join(" ")
        break if start_index + target_words >= words.length

        start_index += step
      end

      chunks
    end
  end
end
