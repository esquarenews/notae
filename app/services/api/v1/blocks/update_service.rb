module Api
  module V1
    module Blocks
      class UpdateService
        def self.call(block:, attributes:)
          block.update(attributes)
          block
        end
      end
    end
  end
end
