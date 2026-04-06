require "../../minecraft/io"
require "./paletted_container"

# Chunk Section (16x16x16 blocks), data format 1.16-1.18
class Rosegold::Section
  alias BlockStateNr = UInt16

  getter block_count : Int16
  getter fluid_count : Int16

  def initialize(io)
    # Number of non-air blocks present in the chunk section. If the block count reaches 0, the whole chunk section is not rendered.
    @block_count = io.read_short
    # 26.1+: fluid count is now sent on the wire (was implicit before)
    @fluid_count = Client.protocol_version >= 775_u32 ? io.read_short : 0_i16

    @blocks = PalettedContainer.new io, 9, 4096
    @biomes = PalettedContainer.new io, 4, 64
  end

  # Creates an empty section (for when no section data is sent)
  def self.empty
    new(empty: true)
  end

  def initialize(empty : Bool)
    @block_count = 0_i16
    @fluid_count = 0_i16
    @blocks = PalettedContainer.air_filled(4096, 9_u8)
    @biomes = PalettedContainer.air_filled(64, 4_u8)
  end

  def write(io)
    io.write_full @block_count
    io.write_full @fluid_count if Client.protocol_version >= 775_u32
    @blocks.write io
    @biomes.write io
  end

  def block_state(index : UInt32) : BlockStateNr
    @blocks[index]
  end

  def set_block_state(index : UInt32, block_state : BlockStateNr) : BlockStateNr
    previous_state = @blocks[index]
    @blocks[index] = block_state

    # Update block count based on air transitions (air, cave_air, void_air)
    air_states = MCData.default.air_states
    if !air_states.includes?(previous_state) # was not air
      @block_count -= 1
    end
    if !air_states.includes?(block_state) # is not air
      @block_count += 1
    end

    previous_state
  end

  def has_only_air? : Bool
    @block_count == 0
  end
end
