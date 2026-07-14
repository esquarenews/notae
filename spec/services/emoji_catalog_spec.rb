require "rails_helper"

RSpec.describe EmojiCatalog do
  it "builds emoji categories from the unicode catalog" do
    categories = described_class.categories

    expect(categories).not_to be_empty
    expect(categories.first).to have_attributes(key: anything, label: anything, emojis: anything)
    expect(categories.first.key).to be_present
    expect(categories.first.label).to be_present
    expect(categories.first.emojis).not_to be_empty
    expect(categories.first.search_terms).to be_present
    expect(categories.first.display_names).to be_present
    expect(categories.first.search_terms[categories.first.emojis.first]).to be_present
    expect(categories.first.display_names[categories.first.emojis.first]).to be_present
  end

  it "indexes common plain-language aliases for obvious emoji searches" do
    categories = described_class.categories
    all_search_terms = categories.each_with_object({}) do |category, memo|
      memo.merge!(category.search_terms)
    end

    dance_terms = all_search_terms.select { |emoji, _| [ "💃", "🕺", "👯", "👯‍♀️", "👯‍♂️", "🧑‍🩰" ].any? { |glyph| emoji.include?(glyph) } }
    doctor_terms = all_search_terms.select { |emoji, _| emoji.include?("⚕") }

    expect(dance_terms.values.join(" ")).to include("dance")
    expect(dance_terms.values.join(" ")).to include("dancer")
    expect(doctor_terms.values.join(" ")).to include("doctor")
    expect(doctor_terms.values.join(" ")).to include("medical")
  end

  it "indexes standardized emoji names, descriptions, aliases, and tags" do
    indexed = described_class.categories.each_with_object({}) do |category, memo|
      category.emojis.each do |emoji|
        memo[emoji] = {
          search_terms: category.search_terms.fetch(emoji),
          display_name: category.display_names.fetch(emoji)
        }
      end
    end

    expect(indexed.fetch("⭐")[:search_terms]).to include("star")
    expect(indexed.fetch("🌟")[:search_terms]).to include("glowing star")
    expect(indexed.fetch("🐱")[:search_terms]).to include("cat face", "pet")
    expect(indexed.fetch("🚗")[:search_terms]).to include("automobile", "red car")
    expect(indexed.fetch("👍🏽")[:search_terms]).to include("thumbs up", "approve")
    expect(indexed.fetch("🌟")[:display_name]).to eq("Glowing star")
  end
end
