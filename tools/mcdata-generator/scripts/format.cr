# Pretty-print game_assets JSON files in place, one record per line (see json_writer.cr).
# Usage: crystal run tools/mcdata-generator/scripts/format.cr -- <file.json> [<file.json> ...]
require "./json_writer"

abort "usage: format.cr <file.json> [<file.json> ...]" if ARGV.empty?

ARGV.each do |path|
  pretty_format_file(path)
  puts "  #{path}: #{File.size(path)} bytes"
end
