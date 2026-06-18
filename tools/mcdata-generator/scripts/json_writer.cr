require "json"

# Shared pretty-printer for the generator's JSON output.
#
# Style: "one record per line". The root container's direct children each go on their own
# line; any nested container with >= JSON_EXPAND_MIN children is also expanded (so the
# blockCollisionShapes blocks/shapes maps stay readable), while smaller ones stay compact.
# No indentation — git diffs become one line per record with only newlines added, so the
# embedded assets barely grow. Numbers keep their source form (2.0 stays 2.0); strings are
# emitted as raw UTF-8.

JSON_EXPAND_MIN = 16

def json_emit_string(io : IO, str : String) : Nil
  io << '"'
  str.each_char do |chr|
    case chr
    when '"'  then io << "\\\""
    when '\\' then io << "\\\\"
    when '\b' then io << "\\b"
    when '\t' then io << "\\t"
    when '\n' then io << "\\n"
    when '\f' then io << "\\f"
    when '\r' then io << "\\r"
    else
      if chr.ord < 0x20
        io << "\\u" << chr.ord.to_s(16).rjust(4, '0')
      else
        io << chr
      end
    end
  end
  io << '"'
end

def json_emit_scalar(io : IO, raw) : Nil
  case raw
  when Nil    then io << "null"
  when Bool   then io << (raw ? "true" : "false")
  when String then json_emit_string(io, raw)
  else             io << raw.to_s # Int64 / Float64
  end
end

def json_emit_compact(io : IO, node : JSON::Any) : Nil
  raw = node.raw
  case raw
  when Hash(String, JSON::Any)
    io << '{'
    first = true
    raw.each do |key, value|
      io << ',' unless first
      first = false
      json_emit_string(io, key)
      io << ':'
      json_emit_compact(io, value)
    end
    io << '}'
  when Array(JSON::Any)
    io << '['
    raw.each_with_index do |value, idx|
      io << ',' if idx > 0
      json_emit_compact(io, value)
    end
    io << ']'
  else
    json_emit_scalar(io, raw)
  end
end

def json_emit(io : IO, node : JSON::Any, root : Bool = false) : Nil
  raw = node.raw
  case raw
  when Hash(String, JSON::Any)
    if !raw.empty? && (root || raw.size >= JSON_EXPAND_MIN)
      io << "{\n"
      first = true
      raw.each do |key, value|
        io << ",\n" unless first
        first = false
        json_emit_string(io, key)
        io << ':'
        json_emit(io, value)
      end
      io << "\n}"
    else
      json_emit_compact(io, node)
    end
  when Array(JSON::Any)
    if !raw.empty? && (root || raw.size >= JSON_EXPAND_MIN)
      io << "[\n"
      raw.each_with_index do |value, idx|
        io << ",\n" if idx > 0
        json_emit(io, value)
      end
      io << "\n]"
    else
      json_emit_compact(io, node)
    end
  else
    json_emit_scalar(io, raw)
  end
end

def pretty_format_file(path : String) : Nil
  doc = JSON.parse(File.read(path))
  File.open(path, "w") do |file|
    json_emit(file, doc, root: true)
    file << '\n'
  end
end
