module Blocks
  class DuplicateService
    def self.call(block:, actor:)
      new(block:, actor:).call
    end

    def initialize(block:, actor:)
      @block = block
      @actor = actor
    end

    def call
      duplicate_branch(source: block, parent_copy: block.parent_block)
    end

    private

    attr_reader :block, :actor

    def duplicate_branch(source:, parent_copy:)
      copy = Block.create!(
        workspace: source.workspace,
        page: source.page,
        parent_block: parent_copy,
        created_by: actor,
        block_type: source.block_type,
        content_json: deep_dup_json(source.content_json),
        embed_url: source.embed_url
      )

      copy.asset.attach(source.asset.blob) if source.asset.attached?

      source.child_blocks.active.ordered.each do |child|
        duplicate_branch(source: child, parent_copy: copy)
      end

      copy
    end

    def deep_dup_json(value)
      return value.deep_dup if value.respond_to?(:deep_dup)

      JSON.parse(value.to_json)
    end
  end
end
