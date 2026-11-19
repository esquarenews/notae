require "spec_helper"
require "pathname"

RSpec.describe "Ruby runtime configuration" do
  let(:root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:ruby_version) { root.join(".ruby-version").read.strip.delete_prefix("ruby-") }

  it "includes the Regexp and String security fixes released in Ruby 4.0.10" do
    expect(Gem::Version.new(ruby_version)).to be >= Gem::Version.new("4.0.10")
  end

  it "uses the same Ruby patch in development, CI, and the production image" do
    docker_version = root.join("Dockerfile").read[/^ARG RUBY_VERSION=(\S+)$/, 1]

    expect(docker_version).to eq(ruby_version)
    expect(RUBY_VERSION).to eq(ruby_version)
  end

  it "defaults deployments to the matching versioned production runtime" do
    expect(root.join("bin/deploy-production").read).to include(
      'RUNTIME_ENV_FILE="${RUNTIME_ENV_FILE:-/etc/notae/ruby-' + ruby_version + '.env}"'
    )
  end
end
