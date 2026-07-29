require "rails_helper"

RSpec.describe "Active Storage security baseline" do
  it "uses the patched Rails 8.1 Active Storage release" do
    expect(Gem::Version.new(ActiveStorage::VERSION::STRING))
      .to be >= Gem::Version.new("8.1.3.1")
  end

  it "refuses to build a production image with an unsupported libvips release" do
    dockerfile = Rails.root.join("Dockerfile").read

    expect(dockerfile).to include("dpkg --compare-versions \"$vips_version\" ge 8.13")
    expect(dockerfile).to include('VIPS_BLOCK_UNTRUSTED="1"')
  end
end
