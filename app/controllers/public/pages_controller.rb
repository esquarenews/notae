module Public
  class PagesController < ApplicationController
    helper Public::PagesHelper

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
      policy.frame_src :self,
                       "https://youtube.com",
                       "https://www.youtube.com",
                       "https://vimeo.com",
                       "https://player.vimeo.com",
                       "https://figma.com",
                       "https://www.figma.com",
                       "https://loom.com",
                       "https://www.loom.com"
      policy.connect_src :none
      policy.worker_src :none
    end

    skip_after_action :verify_pundit_authorization
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :set_share_link
    after_action :set_public_share_security_headers

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
      ShareLinks::LogViewService.call(share_link: @share_link, ip_address: ip_address)
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
