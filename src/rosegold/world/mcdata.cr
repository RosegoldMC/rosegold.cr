require "../versions"
require "json"
require "minecraft-data"
require "./aabb"
require "../models/block"

# Version-selecting facade over the minecraft-data shard: picks the right
# Minecraft::Data for the active protocol and converts its collision shapes
# into rosegold's AABBf geometry.
class Rosegold::MCData
  alias Item = Minecraft::Data::Item
  alias Enchantment = Minecraft::Data::Enchantment
  alias Material = Minecraft::Data::Material
  alias BlockProperty = Minecraft::Data::BlockProperty
  alias BlockPropertyType = Minecraft::Data::BlockPropertyType
  alias BlockCollisionShapes = Minecraft::Data::BlockCollisionShapes
  alias Shape = Minecraft::Data::Shape

  SUPPORTED_VERSIONS = {% begin %}[ {% enabled = Rosegold::ENABLED_PROTOCOLS %}{% for proto in enabled.keys.sort %}{{enabled[proto]}},{% end %} ]{% end %}

  # A process only ever speaks one protocol, so build each version's data on
  # demand rather than parsing every enabled version up front.
  @@cache = {} of UInt32 => MCData
  @@cache_mutex = Mutex.new

  def self.for(protocol : UInt32) : MCData
    @@cache_mutex.synchronize do
      @@cache[protocol] ||= build(protocol)
    end
  end

  def self.default : MCData
    protocol = Client.protocol_version
    protocol = Client::LATEST_PROTOCOL unless Client::SUPPORTED_PROTOCOLS.includes?(protocol)
    self.for(protocol)
  end

  @[Deprecated("Use MCData.default instead for version-aware data")]
  DEFAULT = for(Client::LATEST_PROTOCOL)

  protected def self.build(protocol : UInt32) : MCData
    {% begin %}
    case protocol
    {% for proto in Rosegold::ENABLED_PROTOCOLS.keys.sort %}
      when {{proto}}_u32
        new({{Rosegold::ENABLED_PROTOCOLS[proto]}})
    {% end %}
    else
      raise "Unsupported protocol version: #{protocol}"
    end
    {% end %}
  end

  getter data : Minecraft::Data

  # block state nr -> array of AABBs that combine to make up that block state shape
  getter block_state_collision_shapes : Array(Array(AABBf))

  # block state nr -> boxes of the block's outline (the selection/targeting
  # shape), independent of collision. States share one array per shape ID.
  getter block_state_outline_shapes : Array(Array(AABBf))

  # state nr -> {max horizontal, max vertical} position offset. Outline boxes of
  # these states are stored neutral and shifted by `outline_offset` at use.
  getter block_state_outline_offsets : Hash(UInt16, Tuple(Float64, Float64))

  getter held_outline_shapes : Hash(UInt16, Hash(UInt32, Array(AABBf)))

  delegate items, blocks, materials, enchantments, block_state_names, air_states, to: @data

  # Minecraft::Data.load embeds files at compile time and requires string
  # literals, so the per-version arms are generated from the enabled map.
  # Disabled versions' JSON is never embedded because their arm is not emitted.
  protected def self.data_for(mc_version : String) : Minecraft::Data
    {% begin %}
    {% enabled = Rosegold::ENABLED_PROTOCOLS %}
    case mc_version
    {% for proto in enabled.keys.sort %}
      {% v = enabled[proto] %}
      when {{v}}
        Minecraft::Data.load({{v}})
    {% end %}
    else
      raise "Unsupported version: #{mc_version}"
    end
    {% end %}
  end

  # Disabled versions' outline files are never embedded, as with `data_for`.
  protected def self.outlines_json_for(mc_version : String) : String
    {% begin %}
    {% enabled = Rosegold::ENABLED_PROTOCOLS %}
    case mc_version
    {% for proto in enabled.keys.sort %}
      {% v = enabled[proto] %}
      when {{v}}
        Minecraft::Data.read_asset({{v + "/blockOutlines.json"}})
    {% end %}
    else
      raise "Unsupported version: #{mc_version}"
    end
    {% end %}
  end

  # Row i of `blocks` belongs to the block with vanilla registry ID i, which is
  # its index in blocks.json. A row has one shape for every state or one per state.
  protected def self.build_outline_shapes(data : Minecraft::Data, outlines : Minecraft::Data::BlockOutlines, shapes : Array(Array(AABBf))) : Array(Array(AABBf))
    unless outlines.blocks.size == data.blocks.size
      raise "Block outline data has #{outlines.blocks.size} blocks, expected #{data.blocks.size}"
    end

    max_state = data.blocks.max_of(&.max_state_id)
    result = Array(Array(AABBf)).new(max_state.to_i + 1) { [] of AABBf }
    data.blocks.each_with_index do |block, registry_id|
      row = outlines.blocks[registry_id]
      state_count = block.max_state_id.to_i - block.min_state_id.to_i + 1
      unless row.size == 1 || row.size == state_count
        raise "Block outline row for #{block.id_str} has #{row.size} entries, expected 1 or #{state_count}"
      end
      state_count.times do |offset|
        shape_id = row[row.size == 1 ? 0 : offset]
        result[block.min_state_id.to_i + offset] = shapes[shape_id]
      end
    end
    result
  end

  # Vanilla Mth.getSeed(x, 0, z) based position offset for the block at x, z.
  def outline_offset(state : UInt16, x : Int32, z : Int32) : Tuple(Float64, Float64, Float64)?
    max_horizontal, max_vertical = @block_state_outline_offsets[state]? || return
    seed = (x &* 3129871_i32).to_i64 ^ (z.to_i64 &* 116129781_i64)
    seed = seed &* seed &* 42317861_i64 &+ seed &* 11_i64
    seed >>= 16
    dx = (((seed & 15).to_f32 / 15_f32).to_f64 - 0.5) * 0.5
    dz = ((((seed >> 8) & 15).to_f32 / 15_f32).to_f64 - 0.5) * 0.5
    dy = ((((seed >> 4) & 15).to_f32 / 15_f32).to_f64 - 1.0) * max_vertical
    {dx.clamp(-max_horizontal, max_horizontal), dy, dz.clamp(-max_horizontal, max_horizontal)}
  end

  def initialize(mc_version : String)
    raise "Rosegold.cr only supports #{SUPPORTED_VERSIONS.join(", ")}" unless SUPPORTED_VERSIONS.includes?(mc_version)

    @data = MCData.data_for(mc_version)
    @block_state_collision_shapes = @data.block_state_collision_shapes.map do |shape|
      shape.map { |box| AABBf.new(*box) }
    end
    outlines = Minecraft::Data::BlockOutlines.from_json(MCData.outlines_json_for(mc_version))
    shapes = outlines.shapes.map do |boxes|
      boxes.map do |box|
        raise "Invalid block outline box #{box}" unless box.size == 6
        AABBf.new(box[0].to_f32, box[1].to_f32, box[2].to_f32, box[3].to_f32, box[4].to_f32, box[5].to_f32)
      end
    end
    @block_state_outline_shapes = MCData.build_outline_shapes(@data, outlines, shapes)
    @block_state_outline_offsets = outlines.offsets.to_h { |state, horizontal, vertical| {state.to_u16, {horizontal, vertical}} }
    item_ids = @data.items.to_h { |item| {item.name, item.id} }
    @held_outline_shapes = Hash(UInt16, Hash(UInt32, Array(AABBf))).new
    outlines.held.each do |state, item_name, shape_id|
      (@held_outline_shapes[state.to_u16] ||= Hash(UInt32, Array(AABBf)).new)[item_ids[item_name]] = shapes[shape_id]
    end
  end
end
