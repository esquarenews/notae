require "rails_helper"

RSpec.describe RequestPerformanceInstrumentation, type: :controller do
  controller(ActionController::Base) do
    include RequestPerformanceInstrumentation

    track_request_performance_for :index

    def index
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { User.count }
      end.value

      render plain: "ok"
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  it "does not count SQL issued by another request thread" do
    get :index

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to eq("0")
    expect(response.headers["X-Notae-Perf-Sql-Ms"]).to eq("0.0")
  end
end
