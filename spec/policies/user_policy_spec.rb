require "rails_helper"

RSpec.describe UserPolicy do
  it "allows users to access only their own record" do
    user = User.create!(email: "user-policy@example.com", password: "password123")
    other = User.create!(email: "user-policy-other@example.com", password: "password123")

    expect(described_class.new(user, user).show?).to be(true)
    expect(described_class.new(user, other).show?).to be(false)
  end
end
