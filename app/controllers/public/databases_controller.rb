module Public
  class DatabasesController < ApplicationController
    content_security_policy do |policy|
      policy.default_src :none
      policy.base_uri :none
      policy.form_action :none
      policy.frame_ancestors :none
      policy.object_src :none
      policy.script_src :none
      policy.style_src :self, :unsafe_inline
      policy.font_src :self, :data
      policy.img_src :self, :https, :data, :blob
      policy.media_src :self, :https, :blob
      policy.frame_src :none
      policy.connect_src :none
      policy.worker_src :none
    end

    skip_after_action :verify_pundit_authorization
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :set_share_link
    after_action :set_public_share_security_headers

    def show
      @database = @share_link.database
      @workspace = @database.workspace
      @db_properties = @database.db_properties.order(:position, :created_at).to_a
      @rows = @database.db_rows.where(archived_at: nil).order(:position, :created_at).to_a
      @cells = DbCell.for_database(@database).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
      @visible_properties = @db_properties.first(8)

      @share_link.update!(last_viewed_at: Time.current) if @workspace.analytics_enabled?
    end

    private

    def set_share_link
      @share_link = DatabaseShareLink.for_public_access.find_by!(token: params[:token])
    end

    def render_not_found
      head :not_found
    end

    def set_public_share_security_headers
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
  end
end
