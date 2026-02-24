module Api
  module V1
    module Pages
      class CreateService
        def self.call(workspace:, actor:, attributes:)
          page = workspace.pages.new(attributes)
          page.created_by = actor
          page.save
          page
        end
      end
    end
  end
end
