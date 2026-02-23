module Blocks
  class ReorderService
    def self.call(block:, target_parent_id:, target_index:)
      new(block:, target_parent_id:, target_index:).call
    end

    def initialize(block:, target_parent_id:, target_index:)
      @block = block
      @target_parent_id = target_parent_id
      @target_index = target_index.to_i
    end

    def call
      Block.transaction do
        target_parent = load_target_parent!
        siblings = load_siblings(target_parent).where.not(id: block.id).lock.order(:position).to_a
        new_position = midpoint_position(siblings, target_index)

        if new_position.nil?
          normalize_positions!(siblings)
          siblings = load_siblings(target_parent).where.not(id: block.id).lock.order(:position).to_a
          new_position = midpoint_position(siblings, target_index) || ((siblings.last&.position || 0) + Block::POSITION_GAP)
        end

        block.update!(parent_block: target_parent, position: new_position)
      end

      block
    end

    private

    attr_reader :block, :target_parent_id, :target_index

    def load_target_parent!
      return nil if target_parent_id.blank?

      parent = block.page.blocks.active.find_by(id: target_parent_id)
      raise ActiveRecord::RecordNotFound, "Target parent not found" unless parent

      parent
    end

    def load_siblings(parent)
      block.page.blocks.active.where(parent_block_id: parent&.id)
    end

    def midpoint_position(siblings, index)
      bounded_index = index.clamp(0, siblings.length)
      prev_position = bounded_index.zero? ? 0 : siblings[bounded_index - 1].position
      next_position = bounded_index >= siblings.length ? nil : siblings[bounded_index].position

      return prev_position + Block::POSITION_GAP if next_position.nil?
      return nil if next_position - prev_position <= 1

      prev_position + ((next_position - prev_position) / 2)
    end

    def normalize_positions!(siblings)
      siblings.each_with_index do |sibling, index|
        sibling.update_columns(position: (index + 1) * Block::POSITION_GAP)
      end
    end
  end
end
