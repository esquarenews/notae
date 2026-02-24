module Api
  module V1
    module Blocks
      class CreateService
        def self.call(page:, workspace:, actor:, attributes:)
          block = page.blocks.new(attributes)
          block.workspace = workspace
          block.created_by = actor
          block.save
          block
        end
      end
    end
  end
end
