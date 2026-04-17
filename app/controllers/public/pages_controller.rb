module Public
  class PagesController < ApplicationController
    helper Public::PagesHelper

    skip_after_action :verify_pundit_authorization
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :set_share_link

    def show
      @page = @share_link.page
      @workspace = @page.workspace
      @blocks = @page.blocks.active.ordered.includes(asset_attachment: :blob).to_a
      @blocks_by_parent = @blocks.group_by(&:parent_block_id)

      log_share_link_view!(ip_address: request.remote_ip)
    end

    private

    def set_share_link
      @share_link = ShareLink.for_public_access.find_by!(token: params[:token])
    end

    def log_share_link_view!(ip_address:)
      ShareLink.transaction do
        ShareLinkView.create!(
          workspace: @share_link.workspace,
          page: @share_link.page,
          share_link: @share_link,
          ip_address: ip_address,
          viewed_at: Time.current
        )
        @share_link.update!(last_viewed_at: Time.current)
      end
    end

    def render_not_found
      head :not_found
    end
  end
end
