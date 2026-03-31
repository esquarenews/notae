module PageTabs
  class Resolver
    Result = Struct.new(:group_page, :tabs, keyword_init: true)
    Tab = Struct.new(:page, :database, :active, :label, :icon, :color_key, keyword_init: true)

    def initialize(workspace:, page_scope:, database_scope:, group_page:, current_page: nil, current_database: nil)
      @workspace = workspace
      @page_scope = page_scope
      @database_scope = database_scope
      @group_page = group_page
      @current_page = current_page
      @current_database = current_database
    end

    def call
      return Result.new(group_page: nil, tabs: []) if @group_page.blank?

      child_tab_pages = @page_scope
                          .for_workspace(@workspace)
                          .active
                          .where(parent_page_id: @group_page.id)
                          .order(:created_at)
                          .to_a

      tab_pages = [ @group_page, *child_tab_pages ]
      databases_by_page_id = linked_databases_by_page_id(tab_pages)
      tabs = tab_pages.map { |tab_page| build_tab(tab_page, databases_by_page_id[tab_page.id]) }

      Result.new(group_page: @group_page, tabs: tabs)
    end

    private

    def linked_databases_by_page_id(tab_pages)
      @database_scope
        .for_workspace(@workspace)
        .active
        .where(linked_page_id: tab_pages.map(&:id))
        .order(:created_at)
        .each_with_object({}) do |database, lookup|
          lookup[database.linked_page_id] ||= database
        end
    end

    def build_tab(tab_page, linked_database)
      is_active_page = @current_page.present? && @current_page.id == tab_page.id
      is_active_database = @current_database.present? && @current_database.linked_page_id == tab_page.id

      if @current_database.present? && @current_database.linked_page_id == tab_page.id
        Tab.new(
          page: tab_page,
          database: @current_database,
          active: true,
          label: tab_page.title,
          icon: @current_database.icon.presence || tab_page.icon.presence || "🗃️",
          color_key: tab_page.tab_color.presence || "default"
        )
      elsif is_active_page
        Tab.new(
          page: tab_page,
          active: true,
          label: tab_page.title,
          icon: @current_page.icon.presence || "📄",
          color_key: tab_page.tab_color.presence || "default"
        )
      elsif linked_database.present?
        Tab.new(
          page: tab_page,
          database: linked_database,
          active: is_active_database,
          label: tab_page.title,
          icon: linked_database.icon.presence || tab_page.icon.presence || "🗃️",
          color_key: tab_page.tab_color.presence || "default"
        )
      else
        Tab.new(
          page: tab_page,
          active: is_active_page,
          label: tab_page.title,
          icon: tab_page.icon.presence || "📄",
          color_key: tab_page.tab_color.presence || "default"
        )
      end
    end
  end
end
