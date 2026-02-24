module Api
  module V1
    module Databases
      class CreateService
        def self.call(workspace:, attributes:)
          database = workspace.databases.new(attributes)
          database.save
          database
        end
      end
    end
  end
end
