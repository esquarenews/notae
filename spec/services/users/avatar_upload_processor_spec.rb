require "rails_helper"
require "mini_magick"

RSpec.describe Users::AvatarUploadProcessor do
  def create_png(path:, width:, height:, color: "#10b981")
    MiniMagick::Tool.new("convert") do |convert|
      convert.size "#{width}x#{height}"
      convert.xc color
      convert << path
    end
  end

  it "resizes a large avatar image to the configured max dimension" do
    Tempfile.create([ "avatar-processor", ".png" ]) do |file|
      create_png(path: file.path, width: 2400, height: 1800)
      upload = Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "large-avatar.png")

      payload = described_class.new(upload: upload).call

      begin
        processed_image = MiniMagick::Image.open(payload[:io].path)

        expect(payload[:filename]).to eq("large-avatar.png")
        expect(payload[:content_type]).to eq("image/png")
        expect(processed_image.width).to be <= described_class::MAX_DIMENSION
        expect(processed_image.height).to be <= described_class::MAX_DIMENSION
      ensure
        described_class.close(payload)
      end
    end
  end

  it "rejects unsupported avatar content types" do
    Tempfile.create([ "avatar-processor", ".svg" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "image/svg+xml", original_filename: "avatar.svg")

      expect {
        described_class.new(upload: upload).call
      }.to raise_error(Users::AvatarUploadProcessor::UnsupportedTypeError, "Avatar must be a PNG, JPEG, WebP, or GIF image.")
    end
  end
end
