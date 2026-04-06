require "json"
require "./aabb"
require "../models/block"

# parsed minecraft-data for a particular mc version
class Rosegold::MCData
  private MCD_ROOT = "minecraft-data/data/pc"

  MC1218  = Rosegold::MCData.new "1.21.8"
  MC12111 = Rosegold::MCData.new "1.21.11"
  MC261   = Rosegold::MCData.new "26.1"

  PROTOCOL_VERSION_MAP = {
    772_u32 => MC1218,
    774_u32 => MC12111,
    775_u32 => MC261,
  }

  @[Deprecated("Use MCData.default instead for version-aware data")]
  DEFAULT = MC261

  def self.default : MCData
    PROTOCOL_VERSION_MAP[Client.protocol_version]? || MC261
  end

  getter items : Array(Item)

  getter blocks : Array(Block)

  getter materials : Material

  getter enchantments : Array(Enchantment)

  # block state nr -> "oak_slab[type=top, waterlogged=true]"
  getter block_state_names : Array(String)

  # Set of block state IDs that are air (air, cave_air, void_air)
  getter air_states : Set(UInt16)

  # block state nr -> array of AABBs that combine to make up that block state shape
  # TODO: more compact memory layout: only store one Shape if it's the same for all variants of a block
  getter block_state_collision_shapes : Array(Array(AABBf))

  SUPPORTED_VERSIONS = ["1.21.8", "1.21.11", "26.1"]

  # Must use string literals — read_game_asset is a compile-time macro
  protected def self.assets_for(mc_version : String)
    case mc_version
    when "1.21.8"
      {
        Rosegold.read_game_asset("1.21.8/items.json"),
        Rosegold.read_game_asset("1.21.8/blocks.json"),
        Rosegold.read_game_asset("1.21.8/materials.json"),
        Rosegold.read_game_asset("1.21.8/enchantments.json"),
        Rosegold.read_game_asset("1.21.8/blockCollisionShapes.json"),
      }
    when "1.21.11"
      {
        Rosegold.read_game_asset("1.21.11/items.json"),
        Rosegold.read_game_asset("1.21.11/blocks.json"),
        Rosegold.read_game_asset("1.21.11/materials.json"),
        Rosegold.read_game_asset("1.21.11/enchantments.json"),
        Rosegold.read_game_asset("1.21.11/blockCollisionShapes.json"),
      }
    when "26.1"
      {
        Rosegold.read_game_asset("26.1/items.json"),
        Rosegold.read_game_asset("26.1/blocks.json"),
        Rosegold.read_game_asset("26.1/materials.json"),
        Rosegold.read_game_asset("26.1/enchantments.json"),
        Rosegold.read_game_asset("26.1/blockCollisionShapes.json"),
      }
    else
      raise "Unsupported version: #{mc_version}"
    end
  end

  def initialize(mc_version : String)
    raise "Rosegold.cr only supports #{SUPPORTED_VERSIONS.join(", ")}" unless SUPPORTED_VERSIONS.includes?(mc_version)

    items_json, blocks_json, materials_json, enchantments_json, collision_shapes_json = MCData.assets_for(mc_version)

    @items = Array(Item).from_json(items_json)
    @blocks = Array(Block).from_json(blocks_json)
    @materials = Material.from_json(materials_json)
    @enchantments = Array(Enchantment).from_json(enchantments_json)
    block_collision_shapes_json = BlockCollisionShapes.from_json(collision_shapes_json)

    max_block_state = blocks.flat_map(&.max_state_id).max

    @air_states = Set(UInt16).new
    blocks.each do |block|
      if block.id_str.in?("air", "cave_air", "void_air")
        (block.min_state_id..block.max_state_id).each { |state| @air_states << state }
      end
    end

    @block_state_names = Array(String).new(max_block_state + 1, "")
    blocks.each do |block|
      if block.states.empty?
        block_state_names[block.min_state_id] = block.id_str
      else
        # example (slab): [["type=top", "waterlogged=true"], ["type=top", "waterlogged=false"], ["type=bottom", "waterlogged=true"], ["type=bottom", "waterlogged=false"], ["type=double", "waterlogged=true"], ["type=double", "waterlogged=false"]]
        prop_combos = Indexable.cartesian_product block.states.map { |prop|
          case prop.type
          when BlockPropertyType::ENUM; prop.values.not_nil! # ameba:disable Lint/NotNil
          when BlockPropertyType::INT ; (0...prop.num_values)
          when BlockPropertyType::BOOL; ["true", "false"] # weird order but that's how it is
          else
            raise "Invalid block property type #{prop.type} in #{block.id_str}.#{prop.name}"
          end.map { |value| "#{prop.name}=#{value}" }
        }
        prop_combos.each_with_index do |props, i|
          state_nr = block.min_state_id + i
          block_state_names[state_nr] = block.id_str + "[#{props.join ", "}]"
        end
      end
    end

    # because there's no 1.18/blockCollisionShapes.json we use 1.19
    # all 1.18->1.19 block states stayed the same except leaves (waterlogged) but it still works because all leaves' shapes are the same
    # veryfy by diffing: jq -c '.[]|{name,states:[.states[]|{name,num_values}]}' < 1.18/blocks.json | sort
    @block_state_collision_shapes = Array(Array(AABBf)).new(max_block_state + 1, [] of AABBf)
    blocks.each do |block|
      block_shape_nrs = block_collision_shapes_json.blocks[block.id_str].try do |j|
        j.is_a?(Array) ? j : [j]
      end
      (block.min_state_id..block.max_state_id).each do |state_nr|
        state_nr_in_block = (state_nr - block.min_state_id) % block_shape_nrs.size
        shape_nr = block_shape_nrs[state_nr_in_block]
        shape = block_collision_shapes_json.shapes[shape_nr.to_s]
        block_state_collision_shapes[state_nr] = shape.map { |aabb| AABBf.new *aabb }
      end
    end
  end

  # entries of enchantments.json
  class Enchantment
    include JSON::Serializable

    def initialize(@id : UInt32, @name : String)
    end

    getter id : UInt32
    getter name : String
  end

  # entries of items.json
  class Item
    include JSON::Serializable

    def initialize(@id : UInt32, @name : String, @stack_size : UInt8, @max_durability : UInt16? = nil, @enchant_categories : Array(String)? = nil)
    end

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

  class Material
    include JSON::Serializable
    include JSON::Serializable::Unmapped
  end

  # entries of `states` field in blocks.json
  class BlockProperty
    include JSON::Serializable

    getter name : String
    getter type : BlockPropertyType
    getter num_values : UInt16
    getter values : Array(String)?
  end

  enum BlockPropertyType
    BOOL
    ENUM
    INT
  end

  # root of blockCollisionShapes.json
  class BlockCollisionShapes
    include JSON::Serializable

    # block id string -> block's shape nr (if same for all states) | each block state's shape nr
    getter blocks : Hash(String, UInt16 | Array(UInt16))
    # shape nr -> array of AABBs that combine to make up that block state shape
    getter shapes : Hash(String, Shape)
  end

  alias Shape = Array({Float32, Float32, Float32, Float32, Float32, Float32})
end
