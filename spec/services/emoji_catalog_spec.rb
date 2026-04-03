require "rails_helper"

RSpec.describe EmojiCatalog do
  it "builds emoji categories from the unicode catalog" do
    categories = described_class.categories

    expect(categories).not_to be_empty
    expect(categories.first).to have_attributes(key: anything, label: anything, emojis: anything)
    expect(categories.first.key).to be_present
    expect(categories.first.label).to be_present
    expect(categories.first.emojis).not_to be_empty
  end
end
