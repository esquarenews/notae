require "rails_helper"
require "zip"

RSpec.describe Imports::ContentParser, type: :service do
  def make_io(content)
    io = StringIO.new(content)
    io.rewind
    io
  end

  it "parses markdown headings, lists, and todo items" do
    markdown = <<~MD
      # Roadmap
      - [x] Done item
      - [ ] Pending item
      1. Ordered one
    MD

    result = described_class.parse(filename: "roadmap.md", io: make_io(markdown))

    expect(result.documents.size).to eq(1)
    blocks = result.documents.first.blocks
    expect(blocks.map { |block| block[:block_type] }).to include("heading_1", "todo_list", "ordered_list")
  end

  it "parses html structure into heading and paragraph blocks" do
    html = "<h2>Overview</h2><p>Import <strong>keeps</strong> basics.</p>"

    result = described_class.parse(filename: "overview.html", io: make_io(html))

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.first[:block_type]).to eq("heading_2")
    expect(result.documents.first.blocks.second[:block_type]).to eq("paragraph")
  end

  it "parses csv into table import blocks" do
    csv = "name,score\nA,10\nB,12\n"

    result = described_class.parse(filename: "scores.csv", io: make_io(csv))

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.first[:block_type]).to eq("heading_2")
    expect(result.documents.first.blocks.second[:block_type]).to eq("code_block")
  end

  it "parses docx paragraphs from document.xml" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
          <w:p>
            <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
            <w:r><w:t>Docx heading</w:t></w:r>
          </w:p>
          <w:p><w:r><w:t>Docx paragraph</w:t></w:r></w:p>
        </w:body>
      </w:document>
    XML

    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write(xml)
    end
    buffer.rewind

    result = described_class.parse(filename: "doc.docx", io: make_io(buffer.string))

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.map { |block| block[:block_type] }).to include("heading_1", "paragraph")
  end

  it "parses epub html sections into separate documents" do
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("OEBPS/chapter1.xhtml")
      zip.write("<html><head><title>Chapter 1</title></head><body><h1>Start</h1><p>Body</p></body></html>")
      zip.put_next_entry("OEBPS/chapter2.xhtml")
      zip.write("<html><head><title>Chapter 2</title></head><body><p>More</p></body></html>")
    end
    buffer.rewind

    result = described_class.parse(filename: "book.epub", io: make_io(buffer.string))

    expect(result.documents.size).to eq(2)
    expect(result.documents.map(&:title).join(" ")).to include("Chapter 1", "Chapter 2")
  end

  it "parses zip entries for supported files and skips unsupported ones" do
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("notes.md")
      zip.write("# Zip note")
      zip.put_next_entry("raw.txt")
      zip.write("zip plain text")
      zip.put_next_entry("ignored.bin")
      zip.write("\x00\x01\x02".b)
    end
    buffer.rewind

    result = described_class.parse(filename: "bundle.zip", io: make_io(buffer.string))

    expect(result.documents.size).to eq(2)
    expect(result.skipped_files).to include("ignored.bin")
  end

  it "parses pdf pages through PDF::Reader" do
    fake_reader = instance_double(PDF::Reader, pages: [ instance_double(PDF::Reader::Page, text: "PDF paragraph") ])
    allow(PDF::Reader).to receive(:new).and_return(fake_reader)

    result = described_class.parse(filename: "doc.pdf", io: make_io("%PDF-fake"))

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.first[:block_type]).to eq("paragraph")
  end

  it "falls back gracefully when pdf-reader dependency is unavailable" do
    parser = described_class.new
    hide_const("PDF::Reader") if defined?(PDF::Reader)
    allow(parser).to receive(:require).and_call_original
    allow(parser).to receive(:activate_pdf_reader_load_path).and_return(false)
    allow(parser).to receive(:require).with("pdf/reader").and_raise(LoadError)
    allow(parser).to receive(:require).with("pdf-reader").and_raise(LoadError)

    result = parser.send(:parse_binary, filename: "fallback.pdf", data: "%PDF")

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.first[:content_json].to_s).to include("pdf-reader dependency is missing")
  end

  it "uses pdf-reader require fallback when pdf/reader fails to load" do
    parser = described_class.new
    hide_const("PDF::Reader") if defined?(PDF::Reader)
    allow(parser).to receive(:require).and_call_original
    allow(parser).to receive(:require).with("pdf/reader").and_raise(LoadError)
    allow(parser).to receive(:require).with("pdf-reader") do
      stub_const("PDF::Reader", Class.new)
      true
    end

    expect(parser.send(:ensure_pdf_reader_loaded)).to eq(true)
  end

  it "retries pdf require after activating gem load paths" do
    parser = described_class.new
    hide_const("PDF::Reader") if defined?(PDF::Reader)
    allow(parser).to receive(:activate_pdf_reader_load_path).and_return(true)
    expect(parser).to receive(:require).with("pdf/reader").ordered.and_raise(LoadError)
    expect(parser).to receive(:require).with("pdf-reader").ordered.and_raise(LoadError)
    expect(parser).to receive(:require).with("pdf/reader").ordered do
      stub_const("PDF::Reader", Class.new)
      true
    end

    expect(parser.send(:ensure_pdf_reader_loaded)).to eq(true)
  end

  it "falls back gracefully when nokogiri dependency is unavailable for html" do
    parser = described_class.new
    allow(parser).to receive(:require).and_call_original
    allow(parser).to receive(:require).with("nokogiri").and_raise(LoadError)

    result = parser.send(:parse_binary, filename: "fallback.html", data: "<p>hello</p>")

    expect(result.documents.size).to eq(1)
    expect(result.documents.first.blocks.first[:content_json].to_s).to include("nokogiri dependency is missing")
  end

  it "reports skipped zip import when rubyzip dependency is unavailable" do
    parser = described_class.new
    allow(parser).to receive(:require).and_call_original
    allow(parser).to receive(:require).with("zip").and_raise(LoadError)

    result = parser.send(:parse_binary, filename: "fallback.zip", data: "")

    expect(result.documents).to be_empty
    expect(result.skipped_files.first).to include("ZIP import is unavailable")
  end
end
