module Api
  module V1
    module Databases
      class UpdateService
        def self.call(database:, attributes:)
          database.update(attributes)
          database
        end
      end
    end
  end
end
