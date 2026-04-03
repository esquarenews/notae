require "rails_helper"

RSpec.describe "Development asset config" do
  it "forces dynamic propshaft asset resolution in development" do
    source = Rails.root.join("config/environments/development.rb").read

    expect(source).to include('config.assets.manifest_path = Rails.root.join("tmp/cache/assets/dev/.manifest.json")')
    expect(source).to include("FileUtils.rm_f(config.assets.manifest_path)")
  end
end
