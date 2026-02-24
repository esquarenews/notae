require "rails_helper"

RSpec.describe "Eager load paths" do
  it "includes app/services for service object constants in eager-loaded environments" do
    normalized = Rails.application.config.eager_load_paths.map(&:to_s)
    expect(normalized).to include(Rails.root.join("app/services").to_s)
  end
end
