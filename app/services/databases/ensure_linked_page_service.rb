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
      if database.linked_page.present?
        sync_missing_linked_page_visual_defaults!(database.linked_page)
        return database.linked_page
      end

      ActiveRecord::Base.transaction do
        linked_page = workspace.pages.new(linked_page_attributes)
        linked_page.cover_image.attach(database.cover_image.blob) if database.cover_image.attached?
        Pages::VisualDefaultsService.apply(record: linked_page, source: parent_page)
        linked_page.save!
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

    def sync_missing_linked_page_visual_defaults!(linked_page)
      return unless linked_page.parent_page.blank?

      changed = false
      if linked_page.icon.blank? && database.icon.present?
        linked_page.icon = database.icon
        changed = true
      end

      unless linked_page.cover?
        if database.cover_preset_key.present?
          linked_page.cover_preset_key = database.cover_preset_key
          linked_page.cover_focal_y = database.cover_focal_y || 50
          changed = true
        elsif database.cover_remote_url.present?
          linked_page.cover_remote_url = database.cover_remote_url
          linked_page.cover_remote_thumb_url = database.cover_remote_thumb_url
          linked_page.cover_artist_name = database.cover_artist_name
          linked_page.cover_artist_url = database.cover_artist_url
          linked_page.cover_source_name = database.cover_source_name
          linked_page.cover_source_url = database.cover_source_url
          linked_page.cover_focal_y = database.cover_focal_y || 50
          changed = true
        elsif database.cover_image.attached?
          linked_page.cover_image.attach(database.cover_image.blob)
        end
      end

      linked_page.save! if changed
    end
  end
end
