require "./mcdata"

# Pending block interaction states, separate from authoritative chunk data.
# Each position keeps its latest prediction until a cumulative acknowledgement.
class Rosegold::MiningPrediction
  alias ChunkPos = {Int32, Int32}
  alias BlockPos = {Int32, Int32, Int32}

  record Entry, sequence : Int32, state : UInt16

  # Water and lava are Fluids.WATER / Fluids.LAVA block states; `water_level`
  # is the LiquidBlock LEVEL property (0 = source, 8+ = falling).
  class FluidTable
    getter air_state : UInt16
    getter water_level = Hash(UInt16, UInt8).new
    getter lava_states = Set(UInt16).new
    getter water_source_state : UInt16
    getter water_min_state : UInt16

    def initialize(mc : Rosegold::MCData)
      air = mc.blocks.find! { |block| block.id_str == "air" }
      @air_state = air.min_state_id
      water = mc.blocks.find! { |block| block.id_str == "water" }
      @water_min_state = water.min_state_id
      @water_source_state = water.min_state_id
      lava = mc.blocks.find! { |block| block.id_str == "lava" }
      (lava.min_state_id..lava.max_state_id).each { |state| @lava_states << state }
      (water.min_state_id..water.max_state_id).each do |state|
        @water_level[state] = (state - water.min_state_id).to_u8
      end

      always_water = {"seagrass", "tall_seagrass", "kelp", "kelp_plant", "bubble_column"}
      mc.blocks.each do |block|
        waterlogged = block.states.any? { |prop| prop.name == "waterlogged" }
        next unless waterlogged || always_water.includes?(block.id_str)
        (block.min_state_id..block.max_state_id).each do |state|
          name = mc.block_state_names[state]
          @water_level[state] = 0_u8 if always_water.includes?(block.id_str) || name.includes?("waterlogged=true")
        end
      end
    end
  end

  @@tables = Hash(UInt64, FluidTable).new
  @@tables_mutex = Mutex.new

  def self.fluid_table(mc : Rosegold::MCData) : FluidTable
    @@tables_mutex.synchronize { @@tables[mc.object_id] ||= FluidTable.new(mc) }
  end

  # createLegacyBlock of the fluid occupying `state`: its source/flowing water
  # or lava block state, otherwise air.
  def self.replacement_state(state : UInt16, mc : Rosegold::MCData = Rosegold::MCData.default) : UInt16
    table = fluid_table(mc)
    if table.water_level.has_key?(state)
      return state if state >= table.water_min_state && state < table.water_min_state + 16
      table.water_source_state
    elsif table.lava_states.includes?(state)
      state
    else
      table.air_state
    end
  end

  # Fluid height in blocks of the water in `state` (FlowingFluid#getOwnHeight,
  # amount / 9), or nil when it holds no water.
  def self.water_own_height(state : UInt16, mc : Rosegold::MCData = Rosegold::MCData.default) : Float64?
    table = fluid_table(mc)
    level = table.water_level[state]? || return
    amount = level == 0 ? 8 : (level >= 8 ? 8 : 8 - level)
    amount / 9.0
  end

  def initialize
    @chunks = Hash(ChunkPos, Hash(BlockPos, Entry)).new
  end

  def empty? : Bool
    @chunks.empty?
  end

  def [](x : Int32, y : Int32, z : Int32) : UInt16?
    @chunks[{x >> 4, z >> 4}]?.try(&.[{x, y, z}]?).try(&.state)
  end

  def predict(x : Int32, y : Int32, z : Int32, sequence : Int32, state : UInt16) : Bool
    entries = (@chunks[{x >> 4, z >> 4}] ||= Hash(BlockPos, Entry).new)
    existing = entries[{x, y, z}]?
    return false if existing && existing.sequence > sequence
    entries[{x, y, z}] = Entry.new(sequence, state)
    true
  end

  def acknowledge(sequence : Int32) : Nil
    @chunks.reject! do |_, entries|
      entries.reject! { |_, entry| entry.sequence <= sequence }
      entries.empty?
    end
  end

  def clear_chunk(chunk_pos : ChunkPos) : Nil
    @chunks.delete chunk_pos
  end

  def clear : Nil
    @chunks.clear
  end
end
