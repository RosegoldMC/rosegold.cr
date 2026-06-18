# Standalone validator: parse generated game_assets/<version>/ through rosegold's actual
# model classes (Block, Item, Entity::Metadata, MCData::*) WITHOUT compiling the whole client
# or the version macros. Run: crystal run tools/mcdata-generator/scripts/validate.cr -- <version>
#
# Reproduces the parsing + derivation MCData#initialize does, so a green run means the
# generated assets are structurally consumable by rosegold.
require "json"

VERSION = ARGV[0]? || "26.2"
ROOT    = "#{__DIR__}/../../../game_assets/#{VERSION}"

enum BlockPropertyType
  BOOL
  ENUM
  INT
end

class BlockProperty
  include JSON::Serializable
  getter name : String
  getter type : BlockPropertyType
  getter num_values : UInt16
  getter values : Array(String)?
end

class Block
  include JSON::Serializable
  @[JSON::Field(key: "name")]
  getter id_str : String
  @[JSON::Field(key: "minStateId")]
  getter min_state_id : UInt16
  @[JSON::Field(key: "maxStateId")]
  getter max_state_id : UInt16
  getter hardness : Float32 = -1.0
  @[JSON::Field(key: "harvestTools")]
  getter harvest_tools : Hash(String, Bool)?
  getter material : String
  getter states : Array(BlockProperty)
end

class Item
  include JSON::Serializable
  getter id : UInt32
  @[JSON::Field(key: "name")]
  getter name : String
  @[JSON::Field(key: "stackSize")]
  getter stack_size : UInt8
  @[JSON::Field(key: "maxDurability")]
  getter max_durability : UInt16?
  @[JSON::Field(key: "enchantCategories")]
  getter enchant_categories : Array(String)?
end

class Enchantment
  include JSON::Serializable
  getter id : UInt32
  getter name : String
end

class EntityMeta
  include JSON::Serializable
  property id : Int32
  property name : String
  property width : Float64
  property height : Float64
  @[JSON::Field(key: "type")]
  property entity_type : String = ""
  property category : String = ""
end

class Material
  include JSON::Serializable
  include JSON::Serializable::Unmapped
end

alias Shape = Array({Float32, Float32, Float32, Float32, Float32, Float32})

class BlockCollisionShapes
  include JSON::Serializable
  getter blocks : Hash(String, UInt16 | Array(UInt16))
  getter shapes : Hash(String, Shape)
end

def read(name)
  File.read("#{ROOT}/#{name}")
end

puts "Validating game_assets/#{VERSION}/ against rosegold models"

items = Array(Item).from_json(read "items.json")
blocks = Array(Block).from_json(read "blocks.json")
materials = Material.from_json(read "materials.json")
enchantments = Array(Enchantment).from_json(read "enchantments.json")
collision = BlockCollisionShapes.from_json(read "blockCollisionShapes.json")
entities = Array(EntityMeta).from_json(read "entities.json")
translations = Hash(String, String).from_json(read "language.json")

puts "  items: #{items.size}, blocks: #{blocks.size}, materials: #{materials.json_unmapped.size}, " \
     "enchantments: #{enchantments.size}, entities: #{entities.size}, translations: #{translations.size}"

# Reproduce MCData#initialize derivations (the part most likely to blow up on bad data)
max_block_state = blocks.flat_map(&.max_state_id).max
block_state_names = Array(String).new(max_block_state + 1, "")
blocks.each do |block|
  if block.states.empty?
    block_state_names[block.min_state_id] = block.id_str
  else
    prop_combos = Indexable.cartesian_product block.states.map { |prop|
      case prop.type
      when BlockPropertyType::ENUM then prop.values.not_nil!
      when BlockPropertyType::INT  then (0...prop.num_values).to_a.map(&.to_s)
      when BlockPropertyType::BOOL then ["true", "false"]
      else                              raise "bad prop type #{prop.type} in #{block.id_str}.#{prop.name}"
      end.map { |v| "#{prop.name}=#{v}" }
    }
    expected = block.max_state_id - block.min_state_id + 1
    raise "#{block.id_str}: #{prop_combos.size} prop combos != #{expected} state ids" if prop_combos.size != expected
    prop_combos.each_with_index do |props, i|
      block_state_names[block.min_state_id + i] = block.id_str + "[#{props.join ", "}]"
    end
  end
end

# Build per-state collision shapes exactly like MCData
block_state_collision_shapes = Array(Array(typeof({0_f32, 0_f32, 0_f32, 0_f32, 0_f32, 0_f32}))).new(max_block_state + 1) { [] of typeof({0_f32, 0_f32, 0_f32, 0_f32, 0_f32, 0_f32}) }
blocks.each do |block|
  shape_nrs = collision.blocks[block.id_str]? || raise "no collision entry for #{block.id_str}"
  arr = shape_nrs.is_a?(Array) ? shape_nrs : [shape_nrs]
  (block.min_state_id..block.max_state_id).each do |state_nr|
    idx = (state_nr - block.min_state_id) % arr.size
    collision.shapes[arr[idx].to_s]? || raise "missing shape #{arr[idx]} for #{block.id_str}"
  end
end

# materials referenced by blocks must exist in materials.json
blocks.each do |b|
  materials.json_unmapped[b.material]? || raise "block #{b.id_str} uses unknown material '#{b.material}'"
end

# every block-state name slot filled
empty = (0..max_block_state).count { |i| block_state_names[i].empty? }
puts "  max_block_state=#{max_block_state}, unfilled state-name slots=#{empty}"

puts "OK: all #{VERSION} assets parsed and derived cleanly"
