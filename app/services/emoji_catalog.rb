require "unicode/emoji"
require "gemoji"

class EmojiCatalog
  Category = Struct.new(:key, :label, :emojis, :search_terms, :display_names, keyword_init: true)

  GROUP_SEARCH_ALIASES = {
    "Smileys & Emotion" => %w[smiley smileys face faces happy joy laugh laughing love feeling feelings],
    "People & Body" => %w[people person body human humans],
    "Animals & Nature" => %w[animal animals nature outdoors],
    "Food & Drink" => %w[food foods drink drinks meal meals],
    "Travel & Places" => %w[travel trip trips place places location locations],
    "Activities" => %w[activity activities sport sports game games fun celebration],
    "Objects" => %w[object objects item items thing things tool tools],
    "Symbols" => %w[symbol symbols icon icons sign signs]
  }.freeze

  SUBGROUP_SEARCH_ALIASES = {
    "person-activity" => %w[activity activities movement],
    "person-role" => %w[profession professions worker workers career careers],
    "person-sport" => %w[sport sports athlete athletes exercise exercising workout workouts],
    "person-resting" => %w[rest resting relax relaxing],
    "face-smiling" => %w[smile smiling grin grinning happy happiness laugh laughing],
    "face-affection" => %w[love loving affection heart hearts kiss kissing],
    "face-concerned" => %w[worried concern concerned anxious anxiousness cry crying sad sadness],
    "heart" => %w[heart hearts love loving romance romantic]
  }.freeze

  DIRECT_SEARCH_ALIASES = {
    "💃" => %w[dance dancing dancer salsa disco party],
    "🕺" => %w[dance dancing dancer disco party],
    "👯" => %w[dance dancing dancers party],
    "👯‍♀️" => %w[dance dancing dancers party],
    "👯‍♂️" => %w[dance dancing dancers party],
    "🩰" => %w[dance dancing dancer ballet ballerina]
  }.freeze

  COMPONENT_SEARCH_ALIASES = {
    "⚕" => %w[doctor doctors medical medicine healthcare nurse nurses hospital],
    "🎓" => %w[student students graduate graduates graduation school university],
    "🏫" => %w[school teacher teachers classroom education],
    "⚖" => %w[judge judges justice legal law court],
    "🌾" => %w[farmer farmers farming agriculture],
    "🍳" => %w[chef chefs cook cooks cooking kitchen],
    "🔧" => %w[mechanic mechanics repair fixing tool tools],
    "🏭" => %w[factory industry industrial worker workers],
    "💼" => %w[office business professional work worker workers],
    "🔬" => %w[scientist scientists science lab laboratory research],
    "💻" => %w[developer developers coder coders programmer programmers computer laptop tech],
    "🎤" => %w[singer singers music musician microphone],
    "🎨" => %w[artist artists art painting painter creative],
    "✈" => %w[pilot pilots airplane aviation flying],
    "🚀" => %w[astronaut astronauts space rocket],
    "🚒" => %w[firefighter firefighters fire rescue],
    "🩰" => %w[dance dancing dancer ballet ballerina],
    "🎄" => %w[christmas santa holiday festive],
    "🧚" => %w[fairy fairies magic magical],
    "🧛" => %w[vampire vampires spooky],
    "🧜" => %w[mermaid mermaids merman ocean sea],
    "🧝" => %w[elf elves fantasy],
    "🧟" => %w[zombie zombies undead],
    "🧘" => %w[yoga meditate meditation calm],
    "🛀" => %w[bath bathing relax relaxing],
    "🛌" => %w[bed sleep sleeping rest],
    "❤️" => %w[heart love],
    "🔥" => %w[fire lit hot]
  }.freeze

  class << self
    def categories
      @categories ||= build_categories.freeze
    end

    private

    def build_categories
      Unicode::Emoji.list.each_with_object([]) do |(group_name, subgroup_map), categories|
        emojis = []
        search_terms = {}
        display_names = {}

        subgroup_map.each do |subgroup_name, subgroup_emojis|
          subgroup_emojis.compact.uniq.each do |emoji|
            emojis << emoji
            metadata = emoji_metadata(emoji)
            search_terms[emoji] ||= build_search_terms_for(
              emoji: emoji,
              group_name: group_name,
              subgroup_name: subgroup_name,
              metadata: metadata
            )
            display_names[emoji] ||= metadata[:display_name]
          end
        end

        emojis = emojis.uniq
        next if emojis.empty?

        categories << Category.new(
          key: group_name.to_s.parameterize,
          label: group_name,
          emojis: emojis,
          search_terms: search_terms,
          display_names: display_names
        )
      end
    end

    def build_search_terms_for(emoji:, group_name:, subgroup_name:, metadata:)
      terms = []
      terms << emoji
      terms.concat(normalized_label_terms(group_name))
      terms.concat(normalized_label_terms(subgroup_name))
      terms.concat(metadata[:search_terms])
      terms.concat(GROUP_SEARCH_ALIASES.fetch(group_name.to_s, []))
      terms.concat(SUBGROUP_SEARCH_ALIASES.fetch(subgroup_name.to_s, []))

      DIRECT_SEARCH_ALIASES.each do |glyph, aliases|
        terms.concat(aliases) if emoji.include?(glyph)
      end

      COMPONENT_SEARCH_ALIASES.each do |component, aliases|
        terms.concat(aliases) if emoji.include?(component)
      end

      terms.flat_map { |term| normalized_label_terms(term) }.reject(&:blank?).uniq.join(" ")
    end

    def emoji_metadata(emoji)
      character = Emoji.find_by_unicode(emoji)
      return { display_name: "Use #{emoji}", search_terms: [] } unless character

      display_name = character.description.to_s.humanize.presence || character.name.to_s.humanize
      search_terms = [
        character.name,
        character.description,
        character.category,
        *character.aliases,
        *character.tags
      ]

      { display_name: display_name, search_terms: search_terms }
    end

    def normalized_label_terms(label)
      normalized = label.to_s.downcase.gsub(/[_&-]+/, " ").squeeze(" ").strip
      return [] if normalized.blank?

      [ normalized, *normalized.split ]
    end
  end
end
