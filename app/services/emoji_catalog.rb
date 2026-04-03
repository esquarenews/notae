require "unicode/emoji"

class EmojiCatalog
  Category = Struct.new(:key, :label, :emojis, keyword_init: true)

  class << self
    def categories
      @categories ||= build_categories.freeze
    end

    private

    def build_categories
      Unicode::Emoji.list.each_with_object([]) do |(group_name, subgroup_map), categories|
        emojis = subgroup_map.values.flatten.compact.uniq
        next if emojis.empty?

        categories << Category.new(
          key: group_name.to_s.parameterize,
          label: group_name,
          emojis: emojis
        )
      end
    end
  end
end
