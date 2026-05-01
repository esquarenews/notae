module Api
  module V1
    class DatabaseRowsController < BaseController
      require_api_token_scopes(
        linked_page: ApiToken::SCOPE_DATABASES_WRITE,
        destroy: ApiToken::SCOPE_DATABASES_WRITE
      )

      before_action :set_workspace!
      before_action :set_database!
      before_action :set_db_row!

      def linked_page
        authorize @db_row, :update?

        apply_linked_page_update!
        return render_validation_errors(@db_row) if @db_row.errors.any?
        return render_validation_errors(@db_row) unless @db_row.save

        render_row(status: :ok)
      end

      def destroy
        authorize @db_row, :destroy?

        @db_row.archive! unless @db_row.archived?
        render_row(status: :ok)
      end

      private

      def set_database!
        @database = policy_scope(Database).for_workspace(workspace).active.find(params[:database_id])
      end

      def set_db_row!
        @db_row = policy_scope(DbRow).for_database(@database).find(params[:id])
      end

      def linked_page_params
        params.require(:db_row).permit(:linked_page_id, :link_action)
      end

      def apply_linked_page_update!
        payload = linked_page_params

        case payload[:link_action].to_s
        when "create_page"
          linked_page = create_linked_page_for_row
          @db_row.linked_page = linked_page if linked_page.present?
        when "clear"
          @db_row.linked_page = nil
        else
          unless payload.key?(:linked_page_id)
            @db_row.errors.add(:base, "linked_page_id or link_action is required")
            return
          end

          resolved_page = resolve_linkable_page(payload[:linked_page_id])
          return if resolved_page == :invalid

          @db_row.linked_page = resolved_page
        end
      end

      def create_linked_page_for_row
        page = workspace.pages.new(title: @db_row.title.presence || "Untitled row", created_by: current_user)
        unless policy(page).create?
          @db_row.errors.add(:base, "You are not authorized to create Notarum in this workspace.")
          return nil
        end

        return page if page.save

        @db_row.errors.add(:base, page.errors.full_messages.to_sentence)
        nil
      end

      def resolve_linkable_page(raw_id)
        candidate_id = raw_id.to_s.strip
        return nil if candidate_id.blank?

        linked_page = policy_scope(Page).for_workspace(workspace).active.find_by(id: candidate_id)
        return linked_page if linked_page.present?

        @db_row.errors.add(:linked_page_id, "must reference an accessible page in this workspace")
        :invalid
      end

      def render_row(status:)
        cells = policy_scope(DbCell).for_database(@database).where(db_row_id: @db_row.id).to_a
        render json: {
          data: Api::V1::Serializers::DatabaseRowSerializer.render(@db_row, cells: cells)
        }, status: status
      end
    end
  end
end
