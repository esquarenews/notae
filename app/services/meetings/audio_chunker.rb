require "fileutils"
require "open3"
require "tmpdir"

module Meetings
  class AudioChunker
    class Error < StandardError; end

    Chunk = Struct.new(:path, :start_offset_seconds, :duration_seconds, keyword_init: true)

    DEFAULT_MAX_CHUNK_DURATION_SECONDS = 1200.0
    OUTPUT_EXTENSION = ".mp3".freeze
    OUTPUT_BITRATE = "64k".freeze
    OUTPUT_SAMPLE_RATE = "16000".freeze
    OUTPUT_CHANNELS = "1".freeze

    def self.available?
      executable_path_for("ffmpeg").present? && executable_path_for("ffprobe").present?
    end

    def self.duration_seconds(file_path)
      new.duration_seconds(file_path)
    end

    def self.executable_path_for(binary_name)
      env_key = binary_name == "ffmpeg" ? "FFMPEG_BIN" : "FFPROBE_BIN"
      env_path = ENV.fetch(env_key, "").to_s.strip
      return env_path if env_path.present? && File.executable?(env_path)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        candidate = File.join(directory, binary_name)
        return candidate if File.executable?(candidate) && !File.directory?(candidate)
      end

      nil
    end

    def initialize(max_chunk_duration_seconds: DEFAULT_MAX_CHUNK_DURATION_SECONDS)
      @max_chunk_duration_seconds = max_chunk_duration_seconds.to_f
    end

    def duration_seconds(file_path)
      ffprobe_path = find_executable!("ffprobe")
      stdout, stderr, status = Open3.capture3(
        ffprobe_path,
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        file_path.to_s
      )

      raise Error, "Audio duration probe failed: #{stderr.presence || stdout.presence || 'unknown error'}" unless status.success?

      duration = stdout.to_s.strip.to_f
      raise Error, "Audio duration probe failed: duration unavailable" unless duration.positive?

      duration
    end

    def split!(file_path:, output_dir: nil)
      total_duration = duration_seconds(file_path)
      chunk_starts = chunk_start_offsets_for(total_duration)
      owned_output_dir = output_dir.blank?
      directory = output_dir.presence || Dir.mktmpdir("meeting-audio-chunks")
      ffmpeg_path = find_executable!("ffmpeg")

      chunks = chunk_starts.map.with_index do |start_offset, index|
        duration = [ max_chunk_duration_seconds, total_duration - start_offset ].min
        output_path = File.join(directory, format("chunk-%03d%s", index + 1, OUTPUT_EXTENSION))
        stdout, stderr, status = Open3.capture3(
          ffmpeg_path,
          "-hide_banner",
          "-loglevel", "error",
          "-y",
          "-ss", format("%.3f", start_offset),
          "-i", file_path.to_s,
          "-t", format("%.3f", duration),
          "-vn",
          "-ac", OUTPUT_CHANNELS,
          "-ar", OUTPUT_SAMPLE_RATE,
          "-codec:a", "libmp3lame",
          "-b:a", OUTPUT_BITRATE,
          output_path
        )

        unless status.success? && File.exist?(output_path)
          raise Error, "Audio chunk export failed: #{stderr.presence || stdout.presence || 'unknown error'}"
        end

        Chunk.new(
          path: output_path,
          start_offset_seconds: start_offset,
          duration_seconds: duration
        )
      end

      {
        directory: directory,
        total_duration_seconds: total_duration,
        chunks: chunks
      }
    rescue StandardError
      FileUtils.remove_entry(directory) if owned_output_dir && directory.present? && Dir.exist?(directory)
      raise
    end

    private

    attr_reader :max_chunk_duration_seconds

    def find_executable!(binary_name)
      self.class.executable_path_for(binary_name) || raise(Error, "#{binary_name} is not available")
    end

    def chunk_start_offsets_for(total_duration)
      starts = []
      cursor = 0.0

      while cursor < total_duration
        starts << cursor.round(3)
        cursor += max_chunk_duration_seconds
      end

      starts.presence || [ 0.0 ]
    end
  end
end
