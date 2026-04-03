require "unicode/emoji"

class EmojiCatalog
  Category = Struct.new(:key, :label, :emojis, :search_terms, keyword_init: true)

  class << self
    def categories
      @categories ||= build_categories.freeze
    end

    private

    def build_categories
      Unicode::Emoji.list.each_with_object([]) do |(group_name, subgroup_map), categories|
        emojis = []
        search_terms = {}

        subgroup_map.each do |subgroup_name, subgroup_emojis|
          subgroup_emojis.compact.uniq.each do |emoji|
            emojis << emoji
            search_terms[emoji] ||= [ emoji, group_name.to_s, subgroup_name.to_s.tr("_-", " ") ].join(" ")
          end
        end

        emojis = emojis.uniq
        next if emojis.empty?

        categories << Category.new(
          key: group_name.to_s.parameterize,
          label: group_name,
          emojis: emojis,
          search_terms: search_terms
        )
      end
    end
  end
end
