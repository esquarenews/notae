require "rails_helper"

RSpec.describe Notae::UploadPolicy do
  it "allows safe raster images" do
    Tempfile.create([ "upload-policy", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")

      expect(described_class.validate_cover_image!(upload)).to be(true)
    end
  end

  it "rejects SVG images for inline-rendered uploads" do
    Tempfile.create([ "upload-policy", ".svg" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/svg+xml")

      expect { described_class.validate_cover_image!(upload) }
        .to raise_error(Notae::UploadPolicy::InvalidUpload, /not supported/)
    end
  end
end
