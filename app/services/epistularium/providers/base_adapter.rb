require "base64"
require "digest"
require "mail"
require "nokogiri"

module Epistularium
  module Providers
    class BaseAdapter
      HTML_TAGS = %w[p br ul ol li a strong em b i blockquote pre code h1 h2 h3 h4 h5 h6 table thead tbody tr td th span div hr].freeze
      HTML_ATTRIBUTES = %w[href title target rel colspan rowspan].freeze
      HEADER_KEYS = %w[Subject From To Cc Bcc Reply-To Date Message-ID In-Reply-To References].freeze
      HIDDEN_EMAIL_TOKEN_PATTERN = /\b(hidden|preheader|preview(?:[-_ ]text)?|visually-hidden|sr-only|screen-reader-text)\b/i
      HIDDEN_STYLE_FRAGMENTS = %w[
        display:none
        visibility:hidden
        opacity:0
        max-height:0
        max-width:0
        mso-hide:all
      ].freeze
      CSS_NOISE_MARKERS = %w[
        font-family:
        border-collapse:
        table-layout:
        -webkit-text-size-adjust
        -ms-text-size-adjust
        mso-table-lspace
        mso-table-rspace
        mso-hide:
        @media
      ].freeze

      class << self
        def html_like_content?(raw_content)
          content = raw_content.to_s
          return false if content.blank?
          return false unless content.match?(/<\/?[a-z][\w:-]*[^>]*>/i)

          fragment = email_html_fragment(content)
          fragment.children.any?(&:element?)
        rescue Nokogiri::XML::SyntaxError
          false
        end

        def prepare_email_html(raw_html)
          html = raw_html.to_s
          return "" if html.blank?

          fragment = email_html_fragment(html)
          fragment.css("style, script, noscript, meta, link, title, head, iframe, object, embed, svg").remove
          fragment.xpath("//comment()").remove
          remove_hidden_nodes!(fragment)
          trim_leading_css_noise!(fragment)
          fragment.to_html
        rescue Nokogiri::XML::SyntaxError
          html
        end

        def sanitize_email_html(raw_html)
          ActionController::Base.helpers.sanitize(
            prepare_email_html(raw_html).to_s,
            tags: HTML_TAGS,
            attributes: HTML_ATTRIBUTES
          )
        end

        def plain_text_from_html(raw_html)
          ActionView::Base.full_sanitizer.sanitize(prepare_email_html(raw_html).to_s)
        end

        def normalize_plain_text(raw_text)
          raw_text.to_s
                  .gsub("\u00A0", " ")
                  .gsub(/\r\n?/, "\n")
                  .lines
                  .map(&:rstrip)
                  .join("\n")
                  .gsub(/\n{3,}/, "\n\n")
                  .strip
        end

        def normalize_email_bodies(text_content:, html_content:)
          normalized_text = normalize_plain_text(text_content)
          prepared_html = prepare_email_html(html_content)

          if prepared_html.blank? && html_like_content?(normalized_text)
            prepared_html = prepare_email_html(normalized_text)
            normalized_text = plain_text_from_html(prepared_html)
          elsif prepared_html.present? && css_noise_text?(normalized_text)
            normalized_text = plain_text_from_html(prepared_html)
          elsif normalized_text.blank? && prepared_html.present?
            normalized_text = plain_text_from_html(prepared_html)
          end

          [
            normalize_plain_text(normalized_text).presence,
            sanitize_email_html(prepared_html).presence
          ]
        end

        private

        def email_html_fragment(html)
          document = Nokogiri::HTML.parse(html)
          body = document.at("body")
          if body.present?
            Nokogiri::HTML::DocumentFragment.parse(body.inner_html)
          else
            Nokogiri::HTML::DocumentFragment.parse(html)
          end
        end

        def remove_hidden_nodes!(fragment)
          fragment.css("*").each do |node|
            style_value = node["style"].to_s.downcase.delete(" ")
            hidden = node["hidden"].present? ||
                     node["aria-hidden"].to_s == "true" ||
                     hidden_by_style?(style_value) ||
                     hidden_by_class_or_id?(node)
            node.remove if hidden
          end
        end

        def hidden_by_style?(style_value)
          HIDDEN_STYLE_FRAGMENTS.any? { |fragment| style_value.include?(fragment) }
        end

        def hidden_by_class_or_id?(node)
          tokens = [ node["class"], node["id"] ].compact.join(" ")
          tokens.match?(HIDDEN_EMAIL_TOKEN_PATTERN)
        end

        def trim_leading_css_noise!(node)
          return unless node.respond_to?(:children)

          remove_leading_noise_children!(node)
          node.element_children.each { |child| trim_leading_css_noise!(child) }
        end

        def remove_leading_noise_children!(node)
          loop do
            child = node.children.find { |candidate| !blank_text_node?(candidate) }
            break if child.blank?
            break unless removable_leading_noise_node?(child)

            child.remove
          end
        end

        def blank_text_node?(node)
          node.text? && node.text.to_s.gsub("\u00A0", " ").strip.blank?
        end

        def removable_leading_noise_node?(node)
          return true if blank_text_node?(node)
          return css_noise_text?(node.text) if node.text?
          return false unless node.element?

          node.css("a, img, button, input, form, video, iframe").none? &&
            css_noise_text?(node.text)
        end

        def css_noise_text?(raw_text)
          normalized = normalize_plain_text(raw_text)
          return false if normalized.blank?

          declaration_count = normalized.scan(/[a-z-]+\s*:\s*[^;{}]+;/i).size
          marker_count = CSS_NOISE_MARKERS.count { |marker| normalized.include?(marker) }
          brace_count = normalized.count("{}")

          (marker_count >= 2 && brace_count >= 2) ||
            declaration_count >= 4 ||
            (normalized.include?("@media") && normalized.include?("{"))
        end
      end

      def initialize(account:)
        @account = account
      end

      def sync!(full_backfill: nil, max_messages_per_mailbox: nil, update_cursor: true)
        raise NotImplementedError, "#{self.class.name} does not implement #sync!"
      end

      private

      attr_reader :account

      def upsert_message!(attributes)
        message = account.epistularium_messages.find_or_initialize_by(provider_message_id: attributes.fetch(:provider_message_id))
        message.assign_attributes(attributes.except(:provider_message_id))
        message.workspace = account.workspace
        message.provider_message_id = attributes.fetch(:provider_message_id)
        message.source_checksum = Digest::SHA256.hexdigest(message.search_source_text.to_s)
        message.last_synced_at = Time.current
        message.save!
        message
      end

      def build_message_attributes_from_mail(mail:, mailbox:, provider_message_id:, provider_thread_id: nil, unread:, received_at: nil, snippet: nil, metadata: {}, header_overrides: {})
        headers = serialized_headers(mail).merge(header_overrides.compact)
        body_text, body_html, attachment_metadata = extract_mail_content(mail)
        internet_message_id = headers["Message-ID"].to_s.strip.presence
        sent_at = parse_message_date(headers["Date"], fallback: received_at)
        effective_received_at = received_at || sent_at || Time.current
        normalized_subject_value = normalized_subject(headers["Subject"] || mail.subject)
        inferred_snippet = snippet.to_s.squish.presence || body_text.to_s.squish.truncate(220)

        {
          workspace_id: account.workspace_id,
          epistularium_account_id: account.id,
          provider_message_id: provider_message_id,
          provider_thread_id: provider_thread_id.to_s.strip.presence,
          internet_message_id: internet_message_id,
          mailbox: mailbox.to_s == "sent" ? "sent" : "inbox",
          subject: normalized_subject_value,
          from_name: primary_recipient(parse_addresses(headers["From"])).dig("name"),
          from_email: primary_recipient(parse_addresses(headers["From"])).dig("email"),
          to_recipients_json: parse_addresses(headers["To"]),
          cc_recipients_json: parse_addresses(headers["Cc"]),
          bcc_recipients_json: parse_addresses(headers["Bcc"]),
          reply_to_recipients_json: parse_addresses(headers["Reply-To"]),
          sent_at: sent_at,
          received_at: effective_received_at,
          unread: unread,
          body_text: body_text.presence,
          body_html: body_html.presence,
          snippet: inferred_snippet,
          thread_key: thread_key_for(
            subject: normalized_subject_value,
            provider_thread_id: provider_thread_id,
            internet_message_id: internet_message_id
          ),
          attachment_metadata_json: attachment_metadata,
          headers_json: headers,
          metadata_json: metadata
        }
      end

      def parse_addresses(raw)
        value = raw.to_s.strip
        return [] if value.blank?

        Mail::AddressList.new(value).addresses.filter_map do |address|
          email = address.address.to_s.strip.downcase.presence
          name = address.display_name.to_s.strip.presence
          next if email.blank? && name.blank?

          {
            "name" => name,
            "email" => email
          }.compact
        end
      rescue Mail::Field::ParseError
        []
      end

      def primary_recipient(recipients)
        Array(recipients).first.to_h
      end

      def serialized_headers(mail)
        HEADER_KEYS.each_with_object({}) do |key, headers|
          value = mail.header[key]&.decoded.to_s
          value = value.to_s.strip
          headers[key] = value if value.present?
        end
      end

      def extract_mail_content(mail)
        text_parts = []
        html_parts = []
        attachment_metadata = []

        all_parts = mail.multipart? ? mail.all_parts : [ mail ]
        all_parts.each do |part|
          content_type = part.mime_type.to_s.downcase
          next if content_type.blank?

          if part.attachment? || part.filename.present?
            attachment_metadata << {
              "filename" => part.filename.to_s,
              "mime_type" => content_type,
              "size" => part.body.decoded.to_s.bytesize
            }.compact
            next
          end

          decoded = decoded_part_body(part)
          if content_type.start_with?("text/plain")
            text_parts << decoded
          elsif content_type.start_with?("text/html")
            html_parts << decoded
          end
        end

        body_text, body_html = self.class.normalize_email_bodies(
          text_content: text_parts.reject(&:blank?).join("\n\n"),
          html_content: html_parts.reject(&:blank?).join("\n\n")
        )

        [
          body_text.to_s.presence,
          body_html.to_s.presence,
          attachment_metadata
        ]
      end

      def decoded_part_body(part)
        part.decoded.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        part.decoded.to_s.force_encoding("UTF-8").scrub
      end

      def strip_html(raw_html)
        self.class.plain_text_from_html(raw_html)
      end

      def sanitize_html(raw_html)
        self.class.sanitize_email_html(raw_html)
      end

      def normalize_plain_text(raw_text)
        self.class.normalize_plain_text(raw_text)
      end

      def parse_message_date(raw_value, fallback: nil)
        value = raw_value.to_s.strip
        return fallback if value.blank?

        Time.zone.parse(value)&.utc || fallback
      rescue ArgumentError, TypeError
        fallback
      end

      def normalized_subject(raw_value)
        raw_value.to_s.strip
      end

      def thread_key_for(subject:, provider_thread_id:, internet_message_id:)
        provider_thread_id.to_s.strip.presence ||
          internet_message_id.to_s.strip.presence ||
          subject.to_s.downcase.gsub(/\A(?:re|fwd?):\s*/i, "").presence
      end

      def decode_base64url(value)
        encoded = value.to_s.tr("-_", "+/")
        encoded = "#{encoded}#{'=' * ((4 - encoded.length % 4) % 4)}"
        Base64.decode64(encoded).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      rescue ArgumentError
        ""
      end
    end
  end
end
