require "rails_helper"

RSpec.describe Unsplash::Client do
  it "normalizes popular photo responses and applies referral links" do
    payload = [
      {
        "id" => "photo-123",
        "alt_description" => "Sunlit coast",
        "urls" => {
          "small" => "https://images.unsplash.com/photo-123-small",
          "regular" => "https://images.unsplash.com/photo-123-regular"
        },
        "links" => {
          "download_location" => "https://api.unsplash.com/photos/photo-123/download"
        },
        "user" => {
          "name" => "Ada Artist",
          "links" => {
            "html" => "https://unsplash.com/@adaartist"
          }
        }
      }
    ]

    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(response).to receive(:to_hash).and_return({ "x-total-pages" => [ "9" ] })

    expect(Net::HTTP).to receive(:start).with(
      "api.unsplash.com",
      443,
      use_ssl: true,
      open_timeout: 5,
      read_timeout: 10
    ).and_yield(instance_double(Net::HTTP, request: response))

    result = described_class.new(access_key: "unsplash-test").list_photos(page: 1, per_page: 12)

    expect(result[:total_pages]).to eq(9)
    expect(result[:photos].first).to include(
      id: "photo-123",
      preview_url: "https://images.unsplash.com/photo-123-small",
      full_url: "https://images.unsplash.com/photo-123-regular",
      artist_name: "Ada Artist",
      source_name: "Unsplash",
      download_location: "https://api.unsplash.com/photos/photo-123/download"
    )
    expect(result[:photos].first[:artist_url]).to include("utm_source=notae")
    expect(result[:photos].first[:source_url]).to include("utm_medium=referral")
  end

  it "derives popular-feed total pages from x-total and x-per-page headers when x-total-pages is absent" do
    payload = [
      {
        "id" => "photo-321",
        "alt_description" => "Harbor lights",
        "urls" => {
          "small" => "https://images.unsplash.com/photo-321-small",
          "regular" => "https://images.unsplash.com/photo-321-regular"
        },
        "links" => {
          "download_location" => "https://api.unsplash.com/photos/photo-321/download"
        },
        "user" => {
          "name" => "Kai Artist",
          "links" => {
            "html" => "https://unsplash.com/@kaiartist"
          }
        }
      }
    ]

    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(response).to receive(:to_hash).and_return({
      "x-total" => [ "316740" ],
      "x-per-page" => [ "3" ]
    })

    expect(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

    result = described_class.new(access_key: "unsplash-test").list_photos(page: 1, per_page: 3)

    expect(result[:total_pages]).to eq(105580)
  end

  it "falls back to the requested search page when Unsplash omits page from the body" do
    payload = {
      "total_pages" => 3334,
      "results" => [
        {
          "id" => "photo-222",
          "alt_description" => "Ocean cliff",
          "urls" => {
            "small" => "https://images.unsplash.com/photo-222-small",
            "regular" => "https://images.unsplash.com/photo-222-regular"
          },
          "links" => {
            "download_location" => "https://api.unsplash.com/photos/photo-222/download"
          },
          "user" => {
            "name" => "Mia Artist",
            "links" => {
              "html" => "https://unsplash.com/@miaartist"
            }
          }
        }
      ]
    }

    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(response).to receive(:to_hash).and_return({})

    expect(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

    result = described_class.new(access_key: "unsplash-test").search_photos(query: "ocean", page: 1, per_page: 3)

    expect(result[:page]).to eq(1)
    expect(result[:total_pages]).to eq(3334)
  end

  it "raises a request error for network failures" do
    allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout.new("timed out"))

    expect do
      described_class.new(access_key: "unsplash-test").list_photos(page: 1, per_page: 12)
    end.to raise_error(Unsplash::Client::RequestError, /Unsplash request failed/)
  end

  it "raises a configuration error with the expected key paths when no access key is present" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("UNSPLASH_ACCESS_KEY").and_return(nil)
    allow(Rails.application.credentials).to receive(:dig).with(:unsplash, :access_key).and_return(nil)

    expect do
      described_class.new(access_key: nil).list_photos(page: 1, per_page: 12)
    end.to raise_error(
      Unsplash::Client::ConfigurationError,
      /UNSPLASH_ACCESS_KEY|credentials\[:unsplash\]\[:access_key\]/
    )
  end
end
