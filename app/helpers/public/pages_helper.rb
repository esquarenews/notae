module Public
  module PagesHelper
    def render_public_block_content(block)
      content_tag(:div, class: "notae-public-rich-text") do
        safe_join(render_public_nodes(public_root_nodes(block.content_json)))
      end
    end

    private

    def public_root_nodes(node)
      case node
      when Hash
        node["type"] == "doc" ? Array(node["content"]) : [ node ]
      when Array
        node
      else
        []
      end
    end

    def render_public_nodes(nodes)
      Array(nodes).filter_map { |node| render_public_node(node) }
    end

    def render_public_node(node)
      return unless node.is_a?(Hash)

      case node["type"]
      when "paragraph"
        content_tag(:p, render_public_inline_nodes(node["content"]), class: "notae-public-paragraph")
      when "heading"
        level = node.dig("attrs", "level").to_i
        level = 1 if level <= 0
        level = 6 if level > 6
        content_tag(:"h#{level}", render_public_inline_nodes(node["content"]), class: "notae-public-heading notae-public-heading-#{level}")
      when "blockquote"
        content_tag(:blockquote, safe_join(render_public_nodes(node["content"])), class: "notae-public-blockquote")
      when "bulletList"
        content_tag(:ul, safe_join(render_public_nodes(node["content"])), class: "notae-public-list notae-public-list-bullet")
      when "orderedList"
        options = { class: "notae-public-list notae-public-list-ordered" }
        start = node.dig("attrs", "start").to_i
        options[:start] = start if start > 1
        content_tag(:ol, safe_join(render_public_nodes(node["content"])), options)
      when "taskList"
        content_tag(:ul, safe_join(render_public_nodes(node["content"])), class: "notae-public-list notae-public-task-list")
      when "listItem"
        content_tag(:li, safe_join(render_public_nodes(node["content"])), class: "notae-public-list-item")
      when "taskItem"
        checked = ActiveModel::Type::Boolean.new.cast(node.dig("attrs", "checked"))
        checkbox = tag.input(type: "checkbox", checked: checked, disabled: true, class: "notae-public-task-checkbox")
        body = content_tag(:div, safe_join(render_public_nodes(node["content"])), class: "notae-public-task-body")
        content_tag(:li, safe_join([ checkbox, body ]), class: "notae-public-task-item")
      when "codeBlock"
        content_tag(:pre, class: "notae-public-code") do
          content_tag(:code, public_plain_text(node["content"]))
        end
      when "horizontalRule"
        tag.hr(class: "notae-public-rule")
      when "callout"
        content_tag(:div, safe_join(render_public_nodes(node["content"])), class: "notae-public-callout")
      when "hardBreak"
        tag.br
      when "text"
        render_public_text_node(node)
      else
        safe_join(render_public_nodes(node["content"]))
      end
    end

    def render_public_inline_nodes(nodes)
      safe_join(Array(nodes).filter_map { |node| render_public_inline_node(node) })
    end

    def render_public_inline_node(node)
      return unless node.is_a?(Hash)

      case node["type"]
      when "text"
        render_public_text_node(node)
      when "hardBreak"
        tag.br
      else
        render_public_inline_nodes(node["content"])
      end
    end

    def render_public_text_node(node)
      apply_public_marks(ERB::Util.html_escape(node["text"].to_s), node["marks"])
    end

    def apply_public_marks(content, marks)
      Array(marks).inject(content) do |memo, mark|
        next memo unless mark.is_a?(Hash)

        case mark["type"]
        when "bold"
          content_tag(:strong, memo)
        when "italic"
          content_tag(:em, memo)
        when "underline"
          content_tag(:u, memo)
        when "strike"
          content_tag(:s, memo)
        when "code"
          content_tag(:code, memo, class: "notae-public-inline-code")
        when "link"
          render_public_link_mark(memo, mark["attrs"])
        else
          memo
        end
      end
    end

    def render_public_link_mark(content, attrs)
      attributes = attrs.to_h
      href = public_safe_href(attributes["href"] || attributes[:href])
      return content if href.blank?

      options = {
        href: href,
        class: "notae-public-link"
      }
      target = (attributes["target"] || attributes[:target]).to_s
      options[:target] = target if %w[_blank _self].include?(target)
      options[:rel] = "noopener noreferrer" if target == "_blank"

      content_tag(:a, content, options)
    end

    def public_safe_href(raw_href)
      href = raw_href.to_s.strip
      return if href.blank?
      return href if href.start_with?("/", "#")

      uri = URI.parse(href)
      return href if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return href if uri.scheme == "mailto"

      nil
    rescue URI::InvalidURIError
      nil
    end

    def public_plain_text(nodes)
      Array(nodes).map { |node| public_plain_text_node(node) }.join
    end

    def public_plain_text_node(node)
      return "" unless node.is_a?(Hash)

      case node["type"]
      when "text"
        node["text"].to_s
      when "hardBreak"
        "\n"
      else
        public_plain_text(node["content"])
      end
    end
  end
end
