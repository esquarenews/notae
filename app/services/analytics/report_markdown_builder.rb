module Analytics
  class ReportMarkdownBuilder
    class << self
      def call(snapshot:)
        new(snapshot:).call
      end
    end

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    def call
      sections = [ header, overview, time_by_surface, content_activity, ai_activity ]
      sections << workspace_activity if snapshot.scope == "all"
      sections.compact.join("\n\n")
    end

    private

    attr_reader :snapshot

    def header
      <<~MARKDOWN.strip
        # My activity - #{snapshot.scope_label}

        #{snapshot.date_range.label} · Generated #{snapshot.generated_at.in_time_zone(snapshot.user.time_zone).strftime("%-d %b %Y at %-I:%M %p %Z")}
      MARKDOWN
    end

    def overview
      <<~MARKDOWN.strip
        ## Overview

        - Active time: #{Formatting.duration(snapshot.active_seconds)}
        - Active days: #{snapshot.active_days}
        - Average active day: #{Formatting.duration(snapshot.average_active_seconds)}
        - Longest streak: #{snapshot.longest_streak_days} #{"day".pluralize(snapshot.longest_streak_days)}
      MARKDOWN
    end

    def time_by_surface
      rows = snapshot.surface_breakdown.map do |entry|
        "- #{entry[:label]}: #{Formatting.duration(entry[:seconds])} (#{Formatting.percent(entry[:percent], precision: 1)})"
      end
      rows = [ "- No active time recorded in this period." ] if rows.empty?

      ([ "## Time by area" ] + rows).join("\n\n")
    end

    def content_activity
      rows = snapshot.content_counts.map { |entry| "- #{entry[:label]}: #{entry[:count]}" }
      ([ "## Content and collaboration" ] + rows).join("\n\n")
    end

    def ai_activity
      ai = snapshot.ai_summary
      model_rows = snapshot.ai_models.map { |entry| "  - #{entry[:model]}: #{entry[:count]}" }
      model_rows = [ "  - No models used in this period." ] if model_rows.empty?

      [
        "## Notae AI",
        "- AI calls: #{ai[:requests]}",
        "- Tokens: #{ai[:tokens]}",
        "- Generated writes: #{ai[:generated_writes]}",
        "- Completed actions: #{ai[:completed_actions]}",
        "- Models used:",
        *model_rows
      ].join("\n\n")
    end

    def workspace_activity
      rows = snapshot.workspace_breakdown.map do |entry|
        tracking_note = entry[:tracking_enabled] ? "" : " · tracking off"
        "- #{entry[:name]}: #{Formatting.duration(entry[:active_seconds])}, #{entry[:ai_requests]} AI requests, #{entry[:items_created]} items created#{tracking_note}"
      end

      ([ "## Workspace breakdown" ] + rows).join("\n\n")
    end
  end
end
