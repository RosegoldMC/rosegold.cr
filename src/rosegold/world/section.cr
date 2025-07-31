require "../../minecraft/io"
require "./paletted_container"

# Chunk Section (16x16x16 blocks), data format 1.16-1.18
class Rosegold::Section
  alias BlockStateNr = UInt16

  @block_count : Int16

  def initialize(io)
    # Number of non-air blocks present in the chunk section. If the block count reaches 0, the whole chunk section is not rendered.
    @block_count = io.read_short

    @blocks = PalettedContainer.new io, 9, 4096
    @biomes = PalettedContainer.new io, 4, 64
  end

  # Creates an empty section (for when no section data is sent)
  def self.empty
    new(empty: true)
  end

  def initialize(empty : Bool)
    @block_count = 0_i16
    @blocks = PalettedContainer.air_filled(4096)
    @biomes = PalettedContainer.air_filled(64)
  end

  def write(io)
    io.write_full @block_count
    @blocks.write io
    @biomes.write io
  end

  def block_state(index : UInt32) : BlockStateNr
    @blocks[index]
  end

  def set_block_state(index : UInt32, block_state : BlockStateNr)
    @blocks[index] = block_state
  end
end
