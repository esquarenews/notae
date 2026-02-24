module ShareLinks
  class LogViewService
    class << self
      def call(share_link:, ip_address:, viewed_at: Time.current)
        ShareLink.transaction do
          share_link.share_link_views.create!(
            workspace: share_link.workspace,
            page: share_link.page,
            ip_address: ip_address,
            viewed_at: viewed_at
          )

          share_link.update!(last_viewed_at: viewed_at)
        end
      end
    end
  end
end
