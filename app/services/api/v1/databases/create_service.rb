module Api
  module V1
    module Databases
      class CreateService
        def self.call(workspace:, attributes:, created_by: nil)
          database = workspace.databases.new(attributes)
          database.created_by = created_by if created_by.present?
          database.save
          database
        end
      end
    end
  end
end
