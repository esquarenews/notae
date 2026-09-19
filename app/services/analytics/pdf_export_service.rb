require "prawn"

module Analytics
  class PdfExportService
    Result = Struct.new(:pdf, keyword_init: true)

    PAGE_SIZE = "A4".freeze
    PAGE_LAYOUT = :landscape
    PAGE_MARGIN = 34
    TEXT_COLOR = "292524".freeze
    MUTED_COLOR = "57534E".freeze
    SOFT_COLOR = "78716C".freeze
    BORDER_COLOR = "D6D3D1".freeze
    TRACK_COLOR = "E7E5E4".freeze
    SURFACE_COLOR = "F8F7F6".freeze
    ACCENT_COLOR = "2563EB".freeze

    class << self
      def call(snapshot:)
        new(snapshot:).call
      end
    end

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    def call
      pdf = Prawn::Document.new(
        page_size: PAGE_SIZE,
        page_layout: PAGE_LAYOUT,
        margin: PAGE_MARGIN,
        info: { Title: "Notae analytics - #{snapshot.scope_label}" }
      )
      # The custom font's full embed avoids intermittent missing glyphs in
      # Poppler/Preview when a multi-page report reuses subsetted faces.
      pdf.font(Notae::PdfFontFamily.register(pdf), subset: false)

      draw_summary_page(pdf)
      pdf.start_new_page
      draw_breakdown_page(pdf)
      if snapshot.scope == "all"
        pdf.start_new_page
        draw_workspace_pages(pdf)
      end
      draw_page_numbers(pdf)

      Result.new(pdf: pdf.render)
    end

    private

    attr_reader :snapshot

    def draw_summary_page(pdf)
      draw_header(pdf, title: "My activity", section: snapshot.scope_label)
      draw_kpis(pdf)
      draw_section_title(pdf, "Active time", "#{snapshot.date_range.label} · #{snapshot.date_range.grouping.to_s.humanize.downcase} view")
      draw_trend_chart(pdf)

      pdf.move_down 6
      pdf.fill_color MUTED_COLOR
      pdf.font_size 6.5
      pdf.text("Chart values: #{trend_values_label}")

      pdf.move_down 8
      pdf.fill_color MUTED_COLOR
      pdf.font_size 8
      pdf.text(peak_summary)
      pdf.move_down 6
      pdf.fill_color SOFT_COLOR
      pdf.font_size 7.5
      pdf.text("Active time is recorded only while a top-level Notae view is visible and recently active.")
    end

    def draw_breakdown_page(pdf)
      draw_header(pdf, title: "Activity breakdown", section: snapshot.scope_label)

      top = pdf.cursor
      gutter = 26
      column_width = (pdf.bounds.width - gutter) / 2.0
      left_height = draw_horizontal_section(
        pdf,
        x: 0,
        top: top,
        width: column_width,
        title: "Where your time went",
        entries: snapshot.surface_breakdown,
        value_key: :seconds,
        value_formatter: ->(value) { Formatting.duration(value) }
      )
      right_height = draw_horizontal_section(
        pdf,
        x: column_width + gutter,
        top: top,
        width: column_width,
        title: "Content and collaboration",
        entries: snapshot.content_counts,
        value_key: :count,
        value_formatter: ->(value) { value.to_i.to_s }
      )

      pdf.move_cursor_to(top - [ left_height, right_height ].max - 18)
      draw_ai_summary(pdf)
      draw_privacy_note(pdf)
    end

    def draw_header(pdf, title:, section:)
      pdf.fill_color ACCENT_COLOR
      pdf.font_size 7.5
      pdf.text("NOTAE · PERSONAL ANALYTICS", character_spacing: 0.8, style: :bold)
      pdf.move_down 4
      pdf.fill_color TEXT_COLOR
      pdf.font_size 22
      pdf.text(title, style: :bold)
      pdf.move_down 3
      pdf.fill_color MUTED_COLOR
      pdf.font_size 9
      pdf.text("#{section} · #{snapshot.date_range.label} · Generated #{generated_at_label}")
      pdf.move_down 11
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 14
    end

    def draw_kpis(pdf)
      metrics = [
        [ "Active time", Formatting.duration(snapshot.active_seconds), active_change_label ],
        [ "Active days", snapshot.active_days.to_s, "#{Formatting.duration(snapshot.average_active_seconds)} average" ],
        [ "Content additions", snapshot.content_total.to_s, "#{snapshot.longest_streak_days}-day longest streak" ],
        [ "AI calls", snapshot.ai_summary[:requests].to_s, "#{snapshot.ai_summary[:tokens]} tokens" ]
      ]
      width = pdf.bounds.width / metrics.length
      height = 61
      y = pdf.cursor

      metrics.each_with_index do |(label, value, note), index|
        x = index * width
        pdf.stroke_color BORDER_COLOR
        pdf.stroke_vertical_line(y, y - height, at: x) if index.positive?
        pdf.fill_color SOFT_COLOR
        pdf.font_size 7.5
        pdf.text_box(label, at: [ x + (index.positive? ? 12 : 0), y ], width: width - 12, height: 12)
        pdf.fill_color TEXT_COLOR
        pdf.font_size 17
        pdf.text_box(
          value,
          at: [ x + (index.positive? ? 12 : 0), y - 15 ],
          width: width - 16,
          height: 29,
          style: :bold,
          overflow: :shrink_to_fit,
          valign: :center
        )
        pdf.fill_color SOFT_COLOR
        pdf.font_size 7.3
        pdf.text_box(note, at: [ x + (index.positive? ? 12 : 0), y - 43 ], width: width - 12, height: 12)
      end

      pdf.move_down height
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def draw_section_title(pdf, title, note)
      pdf.fill_color TEXT_COLOR
      pdf.font_size 12
      pdf.text(title, style: :bold)
      pdf.move_down 2
      pdf.fill_color SOFT_COLOR
      pdf.font_size 7.5
      pdf.text(note)
      pdf.move_down 10
    end

    def draw_trend_chart(pdf)
      entries = snapshot.trend_series
      chart_height = 190
      baseline = 24
      top_padding = 18
      plot_height = chart_height - baseline - top_padding
      maximum = [ entries.map { |entry| entry[:seconds] }.max.to_i, 1 ].max

      pdf.bounding_box([ 0, pdf.cursor ], width: pdf.bounds.width, height: chart_height) do
        pdf.fill_color SURFACE_COLOR
        pdf.fill_rectangle([ 0, chart_height ], pdf.bounds.width, chart_height)
        pdf.stroke_color TRACK_COLOR
        4.times do |index|
          y = baseline + ((plot_height / 3.0) * index)
          pdf.stroke_horizontal_line(0, pdf.bounds.width, at: y)
        end

        count = [ entries.length, 1 ].max
        slot_width = pdf.bounds.width / count.to_f
        bar_width = [ slot_width * 0.48, 13 ].min
        label_step = [ (count / 10.0).ceil, 1 ].max

        entries.each_with_index do |entry, index|
          height = entry[:seconds].zero? ? 1.2 : (entry[:seconds].to_f / maximum) * plot_height
          x = (slot_width * index) + ((slot_width - bar_width) / 2.0)
          pdf.fill_color(entry[:seconds].positive? ? ACCENT_COLOR : TRACK_COLOR)
          pdf.fill_rectangle([ x, baseline + height ], bar_width, height)
          next unless (index % label_step).zero? || index == entries.length - 1

          pdf.fill_color SOFT_COLOR
          pdf.font_size 6.5
          pdf.text_box(entry[:label], at: [ slot_width * index, 16 ], width: slot_width * label_step, height: 10, align: :center, overflow: :shrink_to_fit)
        end
      end
    end

    def draw_horizontal_section(pdf, x:, top:, width:, title:, entries:, value_key:, value_formatter:)
      normalized_entries = entries.presence || [ { label: "No activity recorded", value_key => 0 } ]
      maximum = [ normalized_entries.map { |entry| entry[value_key].to_i }.max.to_i, 1 ].max
      row_height = 25
      heading_height = 24
      height = heading_height + (normalized_entries.length * row_height)

      pdf.bounding_box([ x, top ], width: width, height: height) do
        pdf.fill_color TEXT_COLOR
        pdf.font_size 10
        pdf.text(title, style: :bold)
        pdf.move_down 10

        normalized_entries.each do |entry|
          value = entry[value_key].to_i
          label_width = width * 0.38
          value_width = 64
          track_x = label_width
          track_width = width - label_width - value_width - 8
          row_top = pdf.cursor

          pdf.fill_color MUTED_COLOR
          pdf.font_size 7.5
          pdf.text_box(entry[:label], at: [ 0, row_top ], width: label_width - 7, height: 11, overflow: :shrink_to_fit)
          pdf.fill_color TRACK_COLOR
          pdf.fill_rectangle([ track_x, row_top - 2 ], track_width, 5)
          pdf.fill_color ACCENT_COLOR
          pdf.fill_rectangle([ track_x, row_top - 2 ], [ (value.to_f / maximum) * track_width, 1.2 ].max, 5)
          pdf.fill_color TEXT_COLOR
          pdf.text_box(value_formatter.call(value), at: [ width - value_width, row_top ], width: value_width, height: 11, align: :right, style: :bold)
          pdf.move_down row_height
        end
      end

      height
    end

    def draw_ai_summary(pdf)
      draw_section_title(pdf, "Notae AI", "Model calls, generated writes and completed actions")
      metrics = [
        [ "AI calls", snapshot.ai_summary[:requests] ],
        [ "Tokens", snapshot.ai_summary[:tokens] ],
        [ "Generated writes", snapshot.ai_summary[:generated_writes] ],
        [ "Completed actions", snapshot.ai_summary[:completed_actions] ],
        [ "Models used", snapshot.ai_summary[:models_used] ]
      ]
      width = pdf.bounds.width / metrics.length
      y = pdf.cursor

      metrics.each_with_index do |(label, value), index|
        x = index * width
        pdf.fill_color SOFT_COLOR
        pdf.font_size 7
        pdf.text_box(label, at: [ x, y ], width: width - 8, height: 10)
        pdf.fill_color TEXT_COLOR
        pdf.font_size 12
        pdf.text_box(value.to_i.to_s, at: [ x, y - 14 ], width: width - 8, height: 17, style: :bold)
      end
      pdf.move_down 38

      return if snapshot.ai_models.empty?

      models = snapshot.ai_models.map { |entry| "#{entry[:model]} (#{entry[:count]})" }.join(" · ")
      pdf.fill_color MUTED_COLOR
      pdf.font_size 7.5
      pdf.text("Models: #{models}")
      pdf.move_down 12
    end

    def draw_workspace_pages(pdf)
      draw_header(pdf, title: "Across your workspaces", section: snapshot.scope_label)
      pdf.fill_color SOFT_COLOR
      pdf.font_size 7.5
      pdf.text("Only workspaces currently available to you are included.")
      pdf.move_down 13

      snapshot.workspace_breakdown.each_with_index do |entry, index|
        if pdf.cursor < 44
          pdf.start_new_page
          draw_header(pdf, title: "Across your workspaces", section: "Continued")
        end

        pdf.fill_color TEXT_COLOR
        pdf.font_size 7.5
        pdf.text_box(entry[:name], at: [ 0, pdf.cursor ], width: 190, height: 11, style: :bold, overflow: :shrink_to_fit)
        pdf.fill_color MUTED_COLOR
        summary = "#{Formatting.duration(entry[:active_seconds])} · #{entry[:ai_requests]} AI calls · #{entry[:items_created]} items created"
        summary += " · tracking off" unless entry[:tracking_enabled]
        pdf.text_box(summary, at: [ 205, pdf.cursor ], width: pdf.bounds.width - 205, height: 11, overflow: :shrink_to_fit)
        pdf.move_down 17
        unless index == snapshot.workspace_breakdown.length - 1
          pdf.stroke_color TRACK_COLOR
          pdf.stroke_horizontal_line(0, pdf.bounds.width)
          pdf.move_down 7
        end
      end

      pdf.move_down 4
      if pdf.cursor < 34
        pdf.start_new_page
        draw_header(pdf, title: "Across your workspaces", section: "Continued")
      end
      draw_privacy_note(pdf)
    end

    def draw_privacy_note(pdf)
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 7
      pdf.fill_color SOFT_COLOR
      pdf.font_size 6.8
      pdf.text("Privacy: foreground analytics stores only a workspace, broad app area and 30-second time bucket. It does not store titles, URLs, prompts, keystrokes or content.")
    end

    def draw_page_numbers(pdf)
      pdf.number_pages(
        "<page> / <total>",
        at: [ pdf.bounds.right - 42, -15 ],
        width: 42,
        align: :right,
        size: 6.5,
        color: SOFT_COLOR
      )
    end

    def generated_at_label
      snapshot.generated_at.in_time_zone(snapshot.user.time_zone.presence || Time.zone).strftime("%-d %b %Y, %-I:%M %p %Z")
    end

    def active_change_label
      change = snapshot.active_change_percent
      return "No earlier baseline" if change.nil?
      return "No change from prior period" if change.zero?

      "#{change.positive? ? "+" : ""}#{change}% from prior period"
    end

    def peak_summary
      peak = snapshot.peak_day
      return "No active-time intervals were recorded in this period." unless peak&.dig(:seconds).to_i.positive?

      "Peak day: #{peak[:date].strftime("%-d %b %Y")} · #{Formatting.duration(peak[:seconds])}"
    end

    def trend_values_label
      snapshot.trend_series.map do |entry|
        comparison = entry[:previous_seconds].nil? ? "" : " (#{entry[:change_label]})"
        "#{entry[:label]}: #{Formatting.duration(entry[:seconds])}#{comparison}"
      end.join(" · ")
    end
  end
end
