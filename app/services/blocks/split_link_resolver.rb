module Blocks
  class SplitLinkResolver
    SPLIT_SOURCE = "block".freeze

    def self.target_page_id(content_json:)
      new(content_json:).target_page_id
    end

    def self.target_page(content_json:, workspace:)
      page_id = target_page_id(content_json:)
      return nil if page_id.blank?

      workspace.pages.find_by(id: page_id)
    end

    def self.unlink(content_json:)
      new(content_json:).unlink
    end

    def initialize(content_json:)
      @content_json = content_json
    end

    def target_page_id
      extract_target_page_id(content_json)
    end

    def unlink
      payload = deep_dup_json(content_json)
      remove_split_link_marks!(payload)
      payload
    end

    private

    attr_reader :content_json

    def extract_target_page_id(node)
      case node
      when Hash
        marks = Array(node["marks"])
        marks.each do |mark|
          page_id = page_id_from_mark(mark)
          return page_id if page_id.present?
        end

        node.each do |key, value|
          next if key.to_s == "marks"

          page_id = extract_target_page_id(value)
          return page_id if page_id.present?
        end
      when Array
        node.each do |child|
          page_id = extract_target_page_id(child)
          return page_id if page_id.present?
        end
      end

      nil
    end

    def remove_split_link_marks!(node)
      case node
      when Hash
        if node["marks"].is_a?(Array)
          node["marks"] = node["marks"].reject { |mark| split_preview_mark?(mark) }
          node.delete("marks") if node["marks"].empty?
        end

        node.each_value { |value| remove_split_link_marks!(value) }
      when Array
        node.each { |child| remove_split_link_marks!(child) }
      end
    end

    def page_id_from_mark(mark)
      return nil unless split_preview_mark?(mark)

      href = mark.dig("attrs", "href").to_s
      uri = URI.parse(href)
      query = Rack::Utils.parse_nested_query(uri.query)
      query["split_page_id"].presence
    rescue URI::InvalidURIError
      nil
    end

    def split_preview_mark?(mark)
      return false unless mark.is_a?(Hash)
      return false unless mark["type"].to_s == "link"

      href = mark.dig("attrs", "href").to_s
      return false if href.blank?

      uri = URI.parse(href)
      query = Rack::Utils.parse_nested_query(uri.query)
      query["split_source"].to_s == SPLIT_SOURCE && query["split_page_id"].present?
    rescue URI::InvalidURIError
      false
    end

    def deep_dup_json(value)
      return value.deep_dup if value.respond_to?(:deep_dup)

      JSON.parse(value.to_json)
    end
  end
end
