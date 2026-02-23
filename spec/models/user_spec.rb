require "rails_helper"

RSpec.describe User, type: :model do
  it "requires email for authentication" do
    user = described_class.new(password: "password123")

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end

  it "has workspace memberships" do
    association = described_class.reflect_on_association(:memberships)

    expect(association.macro).to eq(:has_many)
  end
end
