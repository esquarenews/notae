require "rails_helper"

RSpec.describe "Block styling CSS" do
  let(:source) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "keeps colored headings inheriting the selected block color" do
    expect(source).to include(".notae-doc-editor.is-color-blue .ProseMirror :is(h1, h2, h3, h4, h5, h6)")
    expect(source).to include(".notae-doc-editor.is-color-red .ProseMirror :is(h1, h2, h3, h4, h5, h6)")
    expect(source).to include("{ color: inherit; }")
  end

  it "defines pastel block highlight styles" do
    expect(source).to include(".notae-doc-editor.is-highlight-peach .ProseMirror")
    expect(source).to include(".notae-doc-editor.is-highlight-lemon .ProseMirror")
    expect(source).to include(".notae-doc-editor.is-highlight-mint .ProseMirror")
    expect(source).to include(".notae-doc-editor.is-highlight-sky .ProseMirror")
    expect(source).to include(".notae-doc-editor.is-highlight-lavender .ProseMirror")
    expect(source).to include(".notae-doc-editor.is-highlight-rose .ProseMirror")
  end
end
