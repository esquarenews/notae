require "rails_helper"

RSpec.describe Kalendarium::GoogleOauthService do
  it "builds a Google OAuth authorization URL with expected params" do
    service = described_class.new(client_id: "google-client", client_secret: "google-secret")
    url = service.authorization_url(
      redirect_uri: "https://example.com/oauth/callback",
      state: "signed-state-token"
    )

    uri = URI.parse(url)
    query = URI.decode_www_form(uri.query.to_s).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(key, value), acc|
      acc[key] << value
    end
    expect(uri.host).to eq("accounts.google.com")
    expect(query["client_id"]).to eq([ "google-client" ])
    expect(query["redirect_uri"]).to eq([ "https://example.com/oauth/callback" ])
    expect(query["response_type"]).to eq([ "code" ])
    expect(query["access_type"]).to eq([ "offline" ])
    expect(query["state"]).to eq([ "signed-state-token" ])
    expect(query["scope"].first).to include("calendar.readonly")
  end

  it "exchanges code for tokens" do
    service = described_class.new(client_id: "google-client", client_secret: "google-secret")
    response = instance_double(Net::HTTPResponse, code: "200", body: {
      access_token: "access-token",
      refresh_token: "refresh-token",
      scope: "https://www.googleapis.com/auth/calendar.readonly",
      token_type: "Bearer",
      expires_in: 3600
    }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)

    payload = service.exchange_code!(code: "auth-code", redirect_uri: "https://example.com/oauth/callback")

    expect(payload[:access_token]).to eq("access-token")
    expect(payload[:refresh_token]).to eq("refresh-token")
    expect(payload[:token_type]).to eq("Bearer")
    expect(payload[:expires_in]).to eq(3600)
  end

  it "raises a clear error when token exchange fails" do
    service = described_class.new(client_id: "google-client", client_secret: "google-secret")
    response = instance_double(Net::HTTPResponse, code: "400", body: { error: "invalid_grant" }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)

    expect do
      service.exchange_code!(code: "bad-code", redirect_uri: "https://example.com/oauth/callback")
    end.to raise_error(Kalendarium::GoogleOauthService::Error, /Google token exchange failed \(400\)/)
  end
end
