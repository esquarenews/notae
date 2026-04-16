require "rails_helper"

RSpec.describe "Authentication styles" do
  it "applies the themed input treatment to password fields as well as email fields" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include('.notae-theme input[type="email"],')
    expect(stylesheet).to include('.notae-theme input[type="password"],')
  end
end
