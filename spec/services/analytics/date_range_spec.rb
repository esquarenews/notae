require "rails_helper"

RSpec.describe Analytics::DateRange do
  let(:today) { Date.new(2026, 7, 13) }

  it "defaults to a 30-day range and chooses a daily chart" do
    range = described_class.new(today: today)

    expect(range.period).to eq("30d")
    expect(range.start_date).to eq(Date.new(2026, 6, 14))
    expect(range.end_date).to eq(today)
    expect(range.days).to eq(30)
    expect(range.grouping).to eq(:day)
  end

  it "supports custom dates and caps expensive ranges at 366 days" do
    range = described_class.new(
      params: { period: "custom", start_date: "2020-01-01", end_date: "2026-07-13" },
      today: today
    )

    expect(range.period).to eq("custom")
    expect(range.days).to eq(366)
    expect(range.end_date).to eq(today)
    expect(range.grouping).to eq(:month)
  end

  it "falls back safely when custom dates are invalid or reversed" do
    invalid = described_class.new(
      params: { period: "custom", start_date: "later", end_date: "earlier" },
      today: today
    )
    reversed = described_class.new(
      params: { period: "custom", start_date: "2026-07-13", end_date: "2026-07-01" },
      today: today
    )

    expect(invalid.period).to eq("30d")
    expect(reversed.period).to eq("30d")
    expect(invalid.days).to eq(30)
    expect(reversed.days).to eq(30)
  end

  it "falls back safely when a custom range is entirely in the future" do
    range = described_class.new(
      params: { period: "custom", start_date: "2026-08-01", end_date: "2026-08-10" },
      today: today
    )

    expect(range.period).to eq("30d")
    expect(range.start_date).to eq(Date.new(2026, 6, 14))
    expect(range.end_date).to eq(today)
    expect(range.days).to eq(30)
  end
end
