# Transform Minecraft jar data into rosegold's slim per-version game_assets schema.
#
# Run: crystal run tools/mcdata-generator/scripts/transform.cr -- \
#        --work work/ --carry ../../game_assets/26.1 --deltas deltas/26.2.json \
#        --entity-classify work/prismarine-1.21.9/entities.json --out ../../game_assets/26.2
#
# Inputs (under --work): reports/ (vanilla --reports), jar-data/tags/{block,item}/,
# jar-data/enchantment/, lang/en_us.json. --carry is the previous version's slim assets
# (runtime values carried forward by NAME); --deltas hand-curates blocks/entities new in
# this version. Output JSON is byte-compatible with Python's json.dump(separators=(",",":"),
# ensure_ascii=True) — see emit/emit_string. The material synthesis and tool-speed logic
# replicate PrismarineJS's minecraft-data-generator (see README for algorithm + provenance).
require "json"

# Recursive value type the emitter accepts. Carried/delta numbers are spliced as JSON::Any
# so they keep their source int-vs-float form; computed numbers use native Int32/Float64.
alias JV = Nil | Bool | Int32 | Int64 | Float64 | String | JSON::Any | Array(JV) | Hash(String, JV)

def strip_ns(name : String) : String
  i = name.index(':')
  i ? name[(i + 1)..] : name
end

def load_json(path : String) : JSON::Any
  JSON.parse(File.read(path))
end

# ---------------------------------------------------------------------------
# Python-compatible JSON output: compact (",":"), ensure_ascii, shortest floats.
# ---------------------------------------------------------------------------
HEX = "0123456789abcdef"

def emit_string(io, s : String)
  io << '"'
  s.each_char do |c|
    o = c.ord
    case o
    when 0x22 then io << "\\\""
    when 0x5C then io << "\\\\"
    when 0x08 then io << "\\b"
    when 0x09 then io << "\\t"
    when 0x0A then io << "\\n"
    when 0x0C then io << "\\f"
    when 0x0D then io << "\\r"
    else
      if o < 0x20 || o > 0x7E
        if o > 0xFFFF
          u = o - 0x10000
          emit_u(io, 0xD800 + (u >> 10))
          emit_u(io, 0xDC00 + (u & 0x3FF))
        else
          emit_u(io, o)
        end
      else
        io << c
      end
    end
  end
  io << '"'
end

def emit_u(io, code : Int32)
  io << "\\u"
  io << HEX[(code >> 12) & 0xF] << HEX[(code >> 8) & 0xF] << HEX[(code >> 4) & 0xF] << HEX[code & 0xF]
end

def emit(io, v : JV)
  case v
  when Nil          then io << "null"
  when Bool         then io << (v ? "true" : "false")
  when String       then emit_string(io, v)
  when Int32, Int64 then io << v.to_s
  when Float64      then io << v.to_s
  when JSON::Any    then emit_any(io, v)
  when Array
    io << '['
    v.each_with_index do |e, i|
      io << ',' if i > 0
      emit(io, e)
    end
    io << ']'
  when Hash
    io << '{'
    first = true
    v.each do |k, val|
      io << ',' unless first
      first = false
      emit_string(io, k)
      io << ':'
      emit(io, val)
    end
    io << '}'
  end
end

def emit_any(io, any : JSON::Any)
  case raw = any.raw
  when Array(JSON::Any)
    io << '['
    raw.each_with_index do |e, i|
      io << ',' if i > 0
      emit_any(io, e)
    end
    io << ']'
  when Hash(String, JSON::Any)
    io << '{'
    first = true
    raw.each do |k, val|
      io << ',' unless first
      first = false
      emit_string(io, k)
      io << ':'
      emit_any(io, val)
    end
    io << '}'
  when Nil     then io << "null"
  when Bool    then io << (raw ? "true" : "false")
  when String  then emit_string(io, raw)
  when Int64   then io << raw.to_s
  when Float64 then io << raw.to_s
  end
end

def write_file(out_dir : String, name : String, value : JV)
  path = "#{out_dir}/#{name}"
  File.open(path, "w") { |f| emit(f, value) }
  puts "  #{name}: #{File.size(path)} bytes"
end

# ---------------------------------------------------------------------------
# Registries from --reports
# ---------------------------------------------------------------------------
def id_map(registries : JSON::Any, registry : String) : Hash(String, Int32)
  map = {} of String => Int32
  registries[registry]["entries"].as_h.each do |k, v|
    map[strip_ns(k)] = v["protocol_id"].as_i
  end
  map
end

# ---------------------------------------------------------------------------
# Block/item tags with recursive #tag expansion
# ---------------------------------------------------------------------------
class Tags
  getter dir : String

  def initialize(@dir : String)
    @cache = {} of String => Set(String)
  end

  def members(tag_path : String) : Set(String)
    if cached = @cache[tag_path]?
      return cached
    end
    @cache[tag_path] = Set(String).new # cycle guard
    result = Set(String).new
    f = "#{@dir}/#{tag_path}.json"
    if File.exists?(f)
      data = load_json(f)
      values = data.as_h? ? data["values"].as_a : data.as_a
      values.each do |v|
        entry = v.as_h? ? v["id"].as_s : v.as_s
        if entry.starts_with?('#')
          result.concat(members(strip_ns(entry[1..])))
        else
          result << strip_ns(entry)
        end
      end
    end
    @cache[tag_path] = result
    result
  end

  def has?(tag_path : String, name : String) : Bool
    members(tag_path).includes?(name)
  end
end

# ---------------------------------------------------------------------------
# items.json
# ---------------------------------------------------------------------------
def enchant_categories_for(item_name : String, item_tags : Tags, category_tags : Array(String)) : Array(String)
  category_tags.select { |c| item_tags.has?("enchantable/#{c}", item_name) }.sort
end

def build_items(registries : JSON::Any, components_dir : String, item_tags : Tags) : Array(JV)
  ids = id_map(registries, "minecraft:item")
  category_tags = [] of String
  ench_dir = "#{item_tags.dir}/enchantable"
  if Dir.exists?(ench_dir)
    category_tags = Dir.glob("#{ench_dir}/*.json").map { |p| File.basename(p, ".json") }
  end

  items = [] of JV
  ids.to_a.sort_by { |(_, iid)| iid }.each do |(name, iid)|
    comp_path = "#{components_dir}/#{name}.json"
    stack_size = 64
    max_durability = nil.as(Int32?)
    if File.exists?(comp_path)
      comps = load_json(comp_path)["components"]?.try(&.as_h) || {} of String => JSON::Any
      stack_size = comps["minecraft:max_stack_size"]?.try(&.as_i) || 64
      max_durability = comps["minecraft:max_damage"]?.try(&.as_i)
    end
    entry = {} of String => JV
    entry["id"] = iid
    entry["name"] = name
    entry["stackSize"] = stack_size
    entry["maxDurability"] = max_durability if max_durability
    unless category_tags.empty?
      cats = enchant_categories_for(name, item_tags, category_tags)
      unless cats.empty?
        arr = [] of JV
        cats.each { |c| arr << c }
        entry["enchantCategories"] = arr
      end
    end
    items << entry
  end
  items
end

# ---------------------------------------------------------------------------
# materials: replicate PrismarineJS MaterialsDataGenerator
# ---------------------------------------------------------------------------
TOOL_SPEED_PREFIX = [
  {"wooden", 2.0}, {"stone", 4.0}, {"iron", 6.0},
  {"diamond", 8.0}, {"netherite", 9.0}, {"golden", 12.0},
]

COMPOSITES = [
  ["plant", "mineable/axe"],
  ["gourd", "mineable/axe"],
  ["leaves", "mineable/hoe"],
  ["leaves", "mineable/axe", "mineable/hoe"],
  ["vine_or_glow_lichen", "plant", "mineable/axe"],
]

SPECIAL_VINE  = Set{"vine", "glow_lichen"}
SPECIAL_COWEB = Set{"cobweb"}
SPECIAL_GOURD = Set{"melon", "pumpkin", "jack_o_lantern"}

def tool_speed_for_item(item_name : String) : Float64
  TOOL_SPEED_PREFIX.each do |(prefix, speed)|
    return speed if item_name.starts_with?(prefix)
  end
  1.0
end

record ToolData,
  tag_to_items : Hash(String, Hash(String, Float64)),
  tool_tag_order : Array(String),
  sword_items : Array(String),
  tool_rules : Hash(String, Array(Tuple(String, Bool)))

# Every TOOL item, every rule (regardless of correct_for_drops), contributes
# {item: name-prefix-speed} to a material named after the rule's block-tag path.
def collect_tool_materials(components_dir : String, item_ids : Hash(String, Int32)) : ToolData
  tag_to_items = {} of String => Hash(String, Float64)
  tool_tag_order = [] of String
  sword_items = [] of String
  tool_rules = {} of String => Array(Tuple(String, Bool))

  item_ids.to_a.sort_by { |(_, id)| id }.each do |(name, _id)|
    comp_path = "#{components_dir}/#{name}.json"
    next unless File.exists?(comp_path)
    comps = load_json(comp_path)["components"]?.try(&.as_h) || {} of String => JSON::Any
    sword_items << name if name.includes?("sword")
    tool = comps["minecraft:tool"]?
    next unless tool
    rules = tool["rules"]?.try(&.as_a) || [] of JSON::Any
    rules.each do |rule|
      blocks = rule["blocks"]?
      next unless blocks && blocks.as_s? # array-of-blocks form not used by vanilla tools
      bs = blocks.as_s
      ok = rule["correct_for_drops"]?.try(&.as_bool?) || false
      if bs.starts_with?('#')
        mat = strip_ns(bs[1..])
        (tool_rules[name] ||= [] of Tuple(String, Bool)) << {"#" + mat, ok}
        unless tag_to_items.has_key?(mat)
          tag_to_items[mat] = {} of String => Float64
          tool_tag_order << mat
        end
        tag_to_items[mat][name] = tool_speed_for_item(name)
      else
        (tool_rules[name] ||= [] of Tuple(String, Bool)) << {strip_ns(bs), ok}
      end
    end
  end
  ToolData.new(tag_to_items, tool_tag_order, sword_items, tool_rules)
end

# Vanilla Tool.isCorrectForDrops: FIRST matching rule decides; correct iff that rule's
# correct_for_drops is true. Returns {item_id => true} sorted by numeric id.
def compute_harvest_tools(block_name : String, tags : Tags,
                          tool_rules : Hash(String, Array(Tuple(String, Bool))),
                          item_ids : Hash(String, Int32)) : Hash(String, Bool)
  result = {} of String => Bool
  tool_rules.each do |item_name, rules|
    correct = false
    rules.each do |(ref, ok)|
      matches = ref.starts_with?('#') ? tags.has?(ref[1..], block_name) : ref == block_name
      if matches
        correct = ok
        break
      end
    end
    result[item_ids[item_name].to_s] = true if correct
  end
  sorted = {} of String => Bool
  result.to_a.sort_by { |(k, _)| k.to_i }.each { |(k, v)| sorted[k] = v }
  sorted
end

# Ordered (material, members) list, first match wins. Composites placed FIRST
# (prismarine addFirst; reversed so the most-specific last-inserted wins).
def build_material_predicates(tags : Tags, tool_tag_order : Array(String)) : Array(Tuple(String, Set(String)))
  base = [] of Tuple(String, Set(String))
  base << {"vine_or_glow_lichen", SPECIAL_VINE}
  base << {"coweb", SPECIAL_COWEB}
  base << {"leaves", tags.members("leaves")}
  base << {"wool", tags.members("wool")}
  base << {"gourd", SPECIAL_GOURD}
  base << {"plant", tags.members("sword_efficient")}
  tool_tag_order.each { |mat| base << {mat, tags.members(mat)} }

  by_name = {} of String => Set(String)
  base.each { |(n, m)| by_name[n] = m }

  composites = [] of Tuple(String, Set(String))
  COMPOSITES.each do |parts|
    members = if parts.all? { |p| by_name.has_key?(p) }
                parts.map { |p| by_name[p] }.reduce { |a, b| a & b }
              else
                Set(String).new
              end
    composites << {parts.join(";"), members}
  end
  composites.reverse + base
end

def material_for_block(block_name : String, ordered : Array(Tuple(String, Set(String)))) : String
  ordered.each do |(mat, members)|
    return mat if members.includes?(block_name)
  end
  "default"
end

def build_materials(tool : ToolData, item_ids : Hash(String, Int32)) : Hash(String, JV)
  speeds = {} of String => Hash(String, Float64)
  speeds["default"] = {} of String => Float64
  add = ->(mat : String, item_name : String, speed : Float64) {
    (speeds[mat] ||= {} of String => Float64)[item_ids[item_name].to_s] = speed
  }

  tool.tag_to_items.each do |mat, items|
    items.each { |item_name, speed| add.call(mat, item_name, speed) }
  end

  if item_ids.has_key?("shears")
    [{"leaves", 15.0}, {"coweb", 15.0}, {"vine_or_glow_lichen", 2.0}, {"wool", 5.0}].each do |(mat, sp)|
      add.call(mat, "shears", sp)
    end
  end
  tool.sword_items.each do |sword|
    add.call("coweb", sword, 15.0)
    ["plant", "leaves", "gourd"].each { |mat| add.call(mat, sword, 1.5) }
  end

  COMPOSITES.each do |parts|
    merged = {} of String => Float64
    parts.each { |p| speeds[p]?.try { |h| merged.merge!(h) } }
    speeds[parts.join(";")] = merged
  end

  out = {} of String => JV
  speeds.each do |mat, items|
    inner = {} of String => JV
    items.each { |k, v| inner[k] = v }
    out[mat] = inner
  end
  out
end

# ---------------------------------------------------------------------------
# blocks.json
# ---------------------------------------------------------------------------
def proptype(values : Array(String)) : Tuple(String, Int32)
  if values == ["true", "false"]
    {"bool", 2}
  elsif values.all? { |v| !v.empty? && v.each_char.all?(&.ascii_number?) }
    {"int", values.size}
  else
    {"enum", values.size}
  end
end

def build_blocks(blocks_report : JSON::Any, tags : Tags, ordered : Array(Tuple(String, Set(String))),
                 carry_by_name : Hash(String, JSON::Any), deltas : JSON::Any,
                 tool_rules : Hash(String, Array(Tuple(String, Bool))),
                 item_ids : Hash(String, Int32)) : Array(Hash(String, JV))
  delta_blocks = deltas["blocks"]?
  out = [] of Hash(String, JV)
  blocks_report.as_h.each do |full_name, bdef|
    name = strip_ns(full_name)
    state_ids = bdef["states"].as_a.map { |s| s["id"].as_i }

    states = [] of JV
    if props = bdef["properties"]?.try(&.as_h)
      props.each do |pname, pvals_any|
        pvals = pvals_any.as_a.map(&.as_s)
        t, nv = proptype(pvals)
        st = {} of String => JV
        st["name"] = pname
        st["type"] = t
        st["num_values"] = nv
        vals = [] of JV
        pvals.each { |x| vals << x }
        st["values"] = vals
        states << st
      end
    end

    carried = carry_by_name[name]?
    delta = delta_blocks.try(&.[name]?)
    hardness : JV = if carried
      carried["hardness"]? || -1.0
    elsif delta
      delta["hardness"]? || -1.0
    else
      -1.0
    end

    requires_tool = (carried && carried["harvestTools"]?) ||
                    (delta && (delta["requiresCorrectToolForDrops"]?.try(&.as_bool?) || false))
    harvest = requires_tool ? compute_harvest_tools(name, tags, tool_rules, item_ids) : nil

    entry = {} of String => JV
    entry["name"] = name
    entry["hardness"] = hardness
    entry["material"] = material_for_block(name, ordered)
    entry["minStateId"] = state_ids.min
    entry["maxStateId"] = state_ids.max
    entry["states"] = states
    if harvest && !harvest.empty?
      hh = {} of String => JV
      harvest.each { |k, v| hh[k] = v }
      entry["harvestTools"] = hh
    end
    out << entry
  end
  out.sort_by! { |b| b["minStateId"].as(Int32) }
  out
end

# ---------------------------------------------------------------------------
# blockCollisionShapes.json — carry shapes by NAME; new blocks reuse an archetype's.
# ---------------------------------------------------------------------------
def build_collision_shapes(blocks : Array(Hash(String, JV)), carry_shapes : JSON::Any,
                           deltas : JSON::Any) : Hash(String, JV)
  carry_block_map = carry_shapes["blocks"].as_h
  carry_shape_def = carry_shapes["shapes"].as_h
  archetypes = deltas["collisionArchetype"]?.try(&.as_h) || {} of String => JSON::Any

  out_blocks = {} of String => JV
  blocks.each do |b|
    name = b["name"].as(String)
    if carry_block_map.has_key?(name)
      out_blocks[name] = carry_block_map[name]
    elsif archetypes.has_key?(name)
      src = archetypes[name].as_s
      raise "archetype source '#{src}' for '#{name}' not found in carry shapes" unless carry_block_map.has_key?(src)
      out_blocks[name] = carry_block_map[src]
    else
      raise "no collision shape for new block '#{name}': add to deltas.collisionArchetype"
    end
  end

  out_shapes = {} of String => JV
  carry_shape_def.each { |k, v| out_shapes[k] = v }

  result = {} of String => JV
  result["blocks"] = out_blocks
  result["shapes"] = out_shapes
  result
end

# ---------------------------------------------------------------------------
# enchantments.json — numeric ids in sorted (alphabetical) registry order.
# ---------------------------------------------------------------------------
def build_enchantments(ench_dir : String) : Array(JV)
  names = Dir.glob("#{ench_dir}/*.json").map { |p| File.basename(p, ".json") }.sort
  out = [] of JV
  names.each_with_index do |n, i|
    e = {} of String => JV
    e["id"] = i
    e["name"] = n
    out << e
  end
  out
end

# ---------------------------------------------------------------------------
# entities.json — dims from carry/delta; type/category from classify source or delta.
# ---------------------------------------------------------------------------
def build_entities(registries : JSON::Any, carry_by_name : Hash(String, JSON::Any),
                   deltas : JSON::Any, classify : Hash(String, JSON::Any)) : Array(JV)
  ids = id_map(registries, "minecraft:entity_type")
  delta_entities = deltas["entities"]?
  out = [] of JV
  ids.to_a.sort_by { |(_, eid)| eid }.each do |(name, eid)|
    carried = carry_by_name[name]?
    delta = delta_entities.try(&.[name]?)
    dims = delta || carried
    cls = (delta && delta["type"]?) ? delta : classify[name]?

    entry = {} of String => JV
    entry["id"] = eid
    entry["name"] = name
    entry["width"] = dims.try(&.["width"]?) || 0.0
    entry["height"] = dims.try(&.["height"]?) || 0.0
    if cls && (t = cls["type"]?)
      entry["type"] = t
    end
    if cls && (cat = cls["category"]?)
      entry["category"] = cat
    end
    out << entry
  end
  out
end

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
work = carry = deltas_path = out_dir = classify_path = nil
i = 0
while i < ARGV.size
  case ARGV[i]
  when "--work"            then work = ARGV[i + 1]; i += 2
  when "--carry"           then carry = ARGV[i + 1]; i += 2
  when "--deltas"          then deltas_path = ARGV[i + 1]; i += 2
  when "--entity-classify" then classify_path = ARGV[i + 1]; i += 2
  when "--out"             then out_dir = ARGV[i + 1]; i += 2
  else
    STDERR.puts "unknown argument: #{ARGV[i]}"
    exit 1
  end
end

abort "missing --work" unless work
abort "missing --carry" unless carry
abort "missing --deltas" unless deltas_path
abort "missing --out" unless out_dir

reports = "#{work}/reports"
registries = load_json("#{reports}/registries.json")
blocks_report = load_json("#{reports}/blocks.json")
components_dir = "#{reports}/minecraft/components/item"
block_tags = Tags.new("#{work}/jar-data/tags/block")
item_tags = Tags.new("#{work}/jar-data/tags/item")
ench_dir = "#{work}/jar-data/enchantment"
deltas = (deltas_path && File.exists?(deltas_path)) ? load_json(deltas_path) : JSON.parse("{}")

item_ids = id_map(registries, "minecraft:item")

carry_block_by_name = {} of String => JSON::Any
load_json("#{carry}/blocks.json").as_a.each { |b| carry_block_by_name[b["name"].as_s] = b }
carry_shapes = load_json("#{carry}/blockCollisionShapes.json")
carry_entity_by_name = {} of String => JSON::Any
load_json("#{carry}/entities.json").as_a.each { |e| carry_entity_by_name[e["name"].as_s] = e }

tool = collect_tool_materials(components_dir, item_ids)
ordered = build_material_predicates(block_tags, tool.tool_tag_order)

classify = {} of String => JSON::Any
if classify_path && File.exists?(classify_path)
  load_json(classify_path).as_a.each { |e| classify[e["name"].as_s] = e }
end

Dir.mkdir_p(out_dir)
puts "Writing slim game_assets to #{out_dir}"

blocks = build_blocks(blocks_report, block_tags, ordered, carry_block_by_name, deltas, tool.tool_rules, item_ids)
blocks_jv = [] of JV
blocks.each { |b| blocks_jv << b }

write_file(out_dir, "items.json", build_items(registries, components_dir, item_tags))
write_file(out_dir, "blocks.json", blocks_jv)
write_file(out_dir, "materials.json", build_materials(tool, item_ids))
write_file(out_dir, "enchantments.json", build_enchantments(ench_dir))
write_file(out_dir, "blockCollisionShapes.json", build_collision_shapes(blocks, carry_shapes, deltas))
write_file(out_dir, "entities.json", build_entities(registries, carry_entity_by_name, deltas, classify))
write_file(out_dir, "language.json", load_json("#{work}/lang/en_us.json"))
puts "done"
