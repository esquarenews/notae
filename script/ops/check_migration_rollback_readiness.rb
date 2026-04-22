#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"

RISKY_PATTERNS = {
  "remove_column" => /\bremove_column\b/,
  "remove_columns" => /\bremove_columns\b/,
  "drop_table" => /\bdrop_table\b/,
  "drop_join_table" => /\bdrop_join_table\b/,
  "change_column" => /\bchange_column\b/,
  "rename_column" => /\brename_column\b/,
  "rename_table" => /\brename_table\b/,
  "execute" => /\bexecute\b/
}.freeze

options = {
  strict: false,
  root: Pathname.pwd
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [--strict] [migration.rb ...]"
  opts.on("--strict", "Exit non-zero when risky migrations need restore-only handling.") do
    options[:strict] = true
  end
  opts.on("--root=PATH", "Repository root used for default db/migrate scan.") do |value|
    options[:root] = Pathname(value)
  end
end

parser.parse!

migration_paths = if ARGV.any?
  ARGV.map { |path| Pathname(path) }
else
  options[:root].join("db/migrate").glob("*.rb")
end

if migration_paths.empty?
  warn "No migration files found."
  exit 1
end

def rollback_path_for(content)
  return "restore-only: explicitly irreversible" if content.match?(/\bIrreversibleMigration\b/)
  return "code-supported: explicit down" if content.match?(/\bdef\s+(?:self\.)?down\b/)
  return "code-supported: up/down pair" if content.match?(/\bdef\s+(?:self\.)?up\b/) && content.match?(/\bdef\s+(?:self\.)?down\b/)
  return "code-supported: reversible block" if content.match?(/\breversible\s+do\b/)
  return "code-supported: reversible change" if content.match?(/\bdef\s+change\b/) && risky_operations(content).empty?

  "restore-only: needs backup rehearsal"
end

def risky_operations(content)
  RISKY_PATTERNS.filter_map do |name, pattern|
    name if content.match?(pattern)
  end
end

restore_only = []

puts "Migration rollback readiness"
puts

migration_paths.sort.each do |path|
  content = path.read
  risky = risky_operations(content)
  rollback_path = rollback_path_for(content)
  status = if risky.empty?
    "OK"
  elsif rollback_path.start_with?("code-supported")
    "REVIEW"
  else
    "BACKUP_REQUIRED"
  end

  relative_path = path.relative_path_from(options[:root]).to_s rescue path.to_s
  puts "#{status.ljust(15)} #{relative_path}"
  puts "  risky operations: #{risky.join(", ")}" if risky.any?
  puts "  rollback path: #{rollback_path}"

  restore_only << path if status == "BACKUP_REQUIRED"
end

puts

if restore_only.any?
  puts "Restore-only migrations require a fresh backup, checksum verification, and restore rehearsal before production deploy."
  exit(options[:strict] ? 1 : 0)
end

puts "All scanned migrations have code-supported rollback or no risky operations."
