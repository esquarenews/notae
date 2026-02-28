module Public
  class DatabasesController < ApplicationController
    skip_after_action :verify_pundit_authorization
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :set_share_link

    def show
      @database = @share_link.database
      @workspace = @database.workspace
      @db_properties = @database.db_properties.order(:position, :created_at).to_a
      @rows = @database.db_rows.where(archived_at: nil).order(:position, :created_at).to_a
      @cells = DbCell.for_database(@database).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
      @visible_properties = @db_properties.first(8)

      @share_link.update!(last_viewed_at: Time.current)
    end

    private

    def set_share_link
      @share_link = DatabaseShareLink.for_public_access.find_by!(token: params[:token])
    end

    def render_not_found
      head :not_found
    end
  end
end
