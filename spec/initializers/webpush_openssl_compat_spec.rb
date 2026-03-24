require "rails_helper"

RSpec.describe "Webpush OpenSSL compatibility" do
  it "rebuilds VAPID keys from encoded keys without raising on OpenSSL 3" do
    generated_key = Webpush.generate_key

    rebuilt_key = described_class_from_keys(generated_key.public_key, generated_key.private_key)

    expect(rebuilt_key.public_key).to eq(generated_key.public_key)
    expect(rebuilt_key.private_key).to eq(generated_key.private_key)
  end

  it "builds a VAPID authorization header from encoded keys" do
    vapid_key = Webpush.generate_key

    request = Webpush::Request.new(
      message: "",
      subscription: {
        endpoint: "https://web.push.apple.com/example",
        keys: {
          p256dh: "p256dh",
          auth: "auth"
        }
      },
      vapid: {
        subject: "mailto:test@example.com",
        public_key: vapid_key.public_key,
        private_key: vapid_key.private_key
      }
    )

    expect { request.build_vapid_header }.not_to raise_error
    expect(request.build_vapid_header).to include("vapid t=")
  end

  def described_class_from_keys(public_key, private_key)
    Webpush::VapidKey.from_keys(public_key, private_key)
  end
end
