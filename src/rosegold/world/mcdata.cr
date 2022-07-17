require "json"
require "./aabb"

# parsed minecraft-data for a particular mc version
class Rosegold::MCData
  private MCD_ROOT = "minecraft-data/data/pc"

  MC118 = Rosegold::MCData.new "1.18"

  getter blocks_by_id : Hash(String, Block)

  # getter block_state_names : Array(String)

  # block state nr -> array of AABBs that combine to make up that block state shape
  getter block_state_collision_shapes : Array(Array(AABB))

  def initialize(mc_version : String)
    # for arbitrary version support, we would need to parse dataPaths.json
    raise "we only support 1.18 for now" if mc_version != "1.18"

    blocks_json = Array(Block).from_json {{read_file "blocks.json"}}
    block_collision_shapes_json = BlockCollisionShapes.from_json {{read_file "blockCollisionShapes.json"}}

    @blocks_by_id = Hash.zip(blocks_json.map &.name, blocks_json)

    max_block_state = blocks_json.map(&.maxStateId).flatten.max

    # because there's no 1.18/blockCollisionShapes.json we use 1.19
    # all 1.18->1.19 block states stayed the same except leaves (waterlogged) but it still works because all leaves' shapes are the same
    # veryfy by diffing: jq -c '.[]|{name,states:[.states[]|{name,num_values}]}' < 1.18/blocks.json | sort
    @block_state_collision_shapes = Array(Array(AABB)).new(max_block_state + 1, [] of AABB)
    blocks_json.each do |block|
      block_shape_nrs = block_collision_shapes_json.blocks[block.name].try do |j|
        j.is_a?(Array) ? j : [j]
      end
      (block.minStateId..block.maxStateId).each do |state_nr|
        state_nr_in_block = (state_nr - block.minStateId) % block_shape_nrs.size
        shape_nr = block_shape_nrs[state_nr_in_block]
        shape = block_collision_shapes_json.shapes[shape_nr.to_s]
        block_state_collision_shapes[state_nr] = shape.map { |aabb| AABB.new *aabb }
      end
    end
  end

  # entries of blocks.json
  class Block
    include JSON::Serializable

    getter id : UInt16
    getter name : String
    getter displayName : String
    getter stackSize : UInt8
    getter minStateId : UInt16
    getter maxStateId : UInt16
    getter defaultState : UInt16
    # Not individual block states, but the properties that, in combination, make up each block state.
    # Empty array if block has only one state.
    getter states : Array(BlockProperty)
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
