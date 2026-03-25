require "rails_helper"

RSpec.describe Meetings::AudioChunker do
  it "parses audio duration from ffprobe output" do
    allow(described_class).to receive(:executable_path_for).with("ffprobe").and_return("/usr/bin/ffprobe")
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).with(
      "/usr/bin/ffprobe",
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      "/tmp/input.webm"
    ).and_return([ "1537.57625\n", "", status ])

    duration = described_class.new.duration_seconds("/tmp/input.webm")

    expect(duration).to eq(1537.57625)
  end

  it "splits long audio into mp3 chunks with stable offsets" do
    chunker = described_class.new(max_chunk_duration_seconds: 600.0)
    output_dir = Dir.mktmpdir("audio-chunker-spec")
    status = instance_double(Process::Status, success?: true)

    allow(chunker).to receive(:duration_seconds).with("/tmp/input.webm").and_return(1250.5)
    allow(described_class).to receive(:executable_path_for).with("ffmpeg").and_return("/usr/bin/ffmpeg")
    allow(Open3).to receive(:capture3) do |*command|
      File.binwrite(command.last, "chunk audio")
      [ "", "", status ]
    end

    result = chunker.split!(file_path: "/tmp/input.webm", output_dir: output_dir)
    chunks = result.fetch(:chunks)

    expect(chunks.map(&:start_offset_seconds)).to eq([ 0.0, 600.0, 1200.0 ])
    expect(chunks.map(&:duration_seconds)).to eq([ 600.0, 600.0, 50.5 ])
    expect(chunks.map { |chunk| File.extname(chunk.path) }.uniq).to eq([ ".mp3" ])
    expect(chunks).to all(satisfy { |chunk| File.exist?(chunk.path) })
  ensure
    FileUtils.remove_entry(output_dir) if output_dir.present? && Dir.exist?(output_dir)
  end
end
