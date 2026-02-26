require "rails_helper"

RSpec.describe "Production SMTP configuration" do
  it "does not require SMTP env vars at boot" do
    source = Rails.root.join("config/environments/production.rb").read

    expect(source).to include('ENV["SMTP_ADDRESS"].presence')
    expect(source).not_to include('ENV.fetch("SMTP_ADDRESS")')
    expect(source).not_to include('ENV.fetch("SMTP_USERNAME")')
    expect(source).not_to include('ENV.fetch("SMTP_PASSWORD")')
  end
end
