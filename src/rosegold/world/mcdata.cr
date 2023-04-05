require "json"
require "./aabb"

# parsed minecraft-data for a particular mc version
class Rosegold::MCData
  private MCD_ROOT = "minecraft-data/data/pc"

  MC118 = Rosegold::MCData.new "1.18"

  getter items : Array(Item)
  getter items_by_id : Hash(String, Item)
  getter items_by_id_int : Hash(UInt32, Item)

  getter blocks : Array(Block)
  getter blocks_by_id : Hash(String, Block)

  getter materials : Material

  # block state nr -> "oak_slab[type=top, waterlogged=true]"
  getter block_state_names : Array(String)

  # block state nr -> array of AABBs that combine to make up that block state shape
  # TODO: more compact memory layout: only store one Shape if it's the same for all variants of a block
  getter block_state_collision_shapes : Array(Array(AABBf))

  def initialize(mc_version : String)
    # for arbitrary version support, we would need to parse dataPaths.json
    raise "we only support 1.18 for now" if mc_version != "1.18"

    @items = Array(Item)
      .from_json(Rosegold.read_game_asset "items.json")
      .unshift(Item.new(id: 0, id_str: "air", display_name: "Air", stack_size: 0))

    @items_by_id = Hash.zip(items.map &.id_str, items)
    @items_by_id_int = Hash.zip(items.map &.id, items)

    @blocks = Array(Block).from_json Rosegold.read_game_asset "blocks.json"
    @blocks_by_id = Hash.zip(blocks.map &.id_str, blocks)

    @materials = Material.from_json Rosegold.read_game_asset "materials.json"

    block_collision_shapes_json = BlockCollisionShapes.from_json Rosegold.read_game_asset "blockCollisionShapes.json"

    max_block_state = blocks.flat_map(&.max_state_id).max

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

  # entries of items.json
  class Item
    include JSON::Serializable

    def initialize(@id : UInt32, @id_str : String, @display_name : String, @stack_size : UInt8, @max_durability : UInt16? = nil, @repair_with : Array(String)? = nil, @enchant_categories : Array(String)? = nil)
    end

    getter id : UInt32
    @[JSON::Field(key: "name")]
    getter id_str : String
    @[JSON::Field(key: "displayName")]
    getter display_name : String
    @[JSON::Field(key: "stackSize")]
    getter stack_size : UInt8
    @[JSON::Field(key: "maxDurability")]
    getter max_durability : UInt16?
    @[JSON::Field(key: "repairWith")]
    getter repair_with : Array(String)?
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
