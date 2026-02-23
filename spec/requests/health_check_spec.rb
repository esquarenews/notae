require "rails_helper"

RSpec.describe "Health checks", type: :request do
  it "returns HTTP 200 for /up" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end
end
