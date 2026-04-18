module Api
  module V1
    class DatabasesController < BaseController
      require_api_token_scopes(
        index: ApiToken::SCOPE_DATABASES_READ,
        show: ApiToken::SCOPE_DATABASES_READ,
        create: ApiToken::SCOPE_DATABASES_WRITE,
        update: ApiToken::SCOPE_DATABASES_WRITE
      )

      before_action :set_workspace!
      before_action :set_database!, only: %i[show update]

      def index
        databases = policy_scope(Database).for_workspace(workspace).active.order(:created_at).includes(:db_properties, :db_rows)

        render json: { data: Api::V1::Serializers::DatabaseSerializer.render_collection(databases) }, status: :ok
      end

      def show
        authorize @database, :show?

        properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
        rows = policy_scope(DbRow).for_database(@database).active.ordered.to_a
        cells = policy_scope(DbCell).for_database(@database)
                                 .where(db_row_id: rows.map(&:id), db_property_id: properties.map(&:id))
                                 .to_a

        render json: {
          data: Api::V1::Serializers::DatabaseSerializer.render(
            @database,
            properties: properties,
            rows: rows,
            cells: cells
          )
        }, status: :ok
      end

      def create
        database = workspace.databases.new(database_params)
        authorize database, :create?

        database = Api::V1::Databases::CreateService.call(
          workspace: workspace,
          created_by: current_user,
          attributes: database_params.to_h
        )
        return render_validation_errors(database) unless database.persisted?

        render json: { data: Api::V1::Serializers::DatabaseSerializer.render_summary(database) }, status: :created
      end

      def update
        authorize @database, :update?

        database = Api::V1::Databases::UpdateService.call(database: @database, attributes: database_params.to_h)
        return render_validation_errors(database) if database.errors.any?

        render json: { data: Api::V1::Serializers::DatabaseSerializer.render_summary(database) }, status: :ok
      end

      private

      def set_database!
        @database = policy_scope(Database).for_workspace(workspace).active.find(params[:id])
      end

      def database_params
        params.require(:database).permit(:name)
      end
    end
  end
end
