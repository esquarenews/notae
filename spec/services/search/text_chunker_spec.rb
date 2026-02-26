require "rails_helper"

RSpec.describe Search::TextChunker do
  it "splits text into overlapping chunks" do
    text = Array.new(420) { |index| "word#{index}" }.join(" ")

    chunks = described_class.call(text, target_words: 120, overlap_words: 20)

    expect(chunks.length).to be >= 4
    expect(chunks.first.split.length).to eq(120)
    expect(chunks.last).to include("word419")
  end

  it "returns an empty array for blank input" do
    expect(described_class.call("   ")).to eq([])
  end
end
