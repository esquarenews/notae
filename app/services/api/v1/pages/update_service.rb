module Api
  module V1
    module Pages
      class UpdateService
        def self.call(page:, attributes:)
          page.update(attributes)
          page
        end
      end
    end
  end
end
