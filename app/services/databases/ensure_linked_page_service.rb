module Databases
  class EnsureLinkedPageService
    def self.call(database:, actor: nil, parent_page: nil, title: nil)
      new(database:, actor:, parent_page:, title:).call
    end

    def initialize(database:, actor: nil, parent_page: nil, title: nil)
      @database = database
      @actor = actor
      @parent_page = parent_page
      @title = title
    end

    def call
      return database.linked_page if database.linked_page.present?

      ActiveRecord::Base.transaction do
        linked_page = workspace.pages.create!(linked_page_attributes)
        linked_page.cover_image.attach(database.cover_image.blob) if database.cover_image.attached?
        database.update!(linked_page: linked_page)
        linked_page
      end
    end

    private

    attr_reader :database, :actor, :parent_page, :title

    def workspace
      database.workspace
    end

    def linked_page_attributes
      {
        title: title.presence || database.name.presence || "Untitled grid",
        parent_page: parent_page,
        created_by: actor || database.created_by,
        icon: database.icon.presence,
        cover_preset_key: database.cover_preset_key.presence,
        cover_focal_y: database.cover_focal_y || 50,
        font_style: database.font_style.presence || "default",
        small_text: database.small_text.nil? ? false : database.small_text
      }
    end
  end
end
