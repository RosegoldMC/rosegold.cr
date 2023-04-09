require "../../minecraft/nbt"
require "./paletted_container"

class Rosegold::Chunk
  alias BlockStateNr = UInt16

  getter x : Int32, z : Int32
  getter sections : Array(Section)
  property block_entities = Array(BlockEntity).new
  property heightmaps : Minecraft::NBT::Tag = Minecraft::NBT::CompoundTag.new
  property light_data = Bytes.empty
  private getter min_y : Int32

  def initialize(@x, @z, io, dimension : Dimension)
    @min_y = dimension.min_y
    section_count = dimension.world_height >> 4
    @sections = Array(Section).new(section_count) { Section.new io }
  end

  def data : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      @sections.each &.write io
    end.to_slice
  end

  # Returns nil if outside world vertically.
  def block_state(x : Int32, y : Int32, z : Int32) : BlockStateNr | Nil
    x, z = x & 15, z & 15
    section = sections[(y - min_y) >> 4]? || return nil
    index = (((y - min_y) & 15) << 8) | (z << 4) | x
    section.block_state index.to_u32
  end

  def set_block_state(x : Int32, y : Int32, z : Int32, block_state : BlockStateNr)
    x, z = x & 15, z & 15
    section = sections[(y - min_y) >> 4]
    index = (((y - min_y) & 15) << 8) | (z << 4) | x
    section.set_block_state index.to_u32, block_state
  end

  # Chunk Section (16x16x16 blocks), data format 1.16-1.18
  class Section
    @block_count : Int16

    def initialize(io)
      # Number of non-air blocks present in the chunk section. If the block count reaches 0, the whole chunk section is not rendered.
      @block_count = io.read_short
      @blocks = PalettedContainer.new io, 9, 4096
      @biomes = PalettedContainer.new io, 4, 64
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
      # TODO update @block_count
    end
  end

  struct BlockEntity
    property x : Int32, y : Int32, z : Int32
    property type : UInt32
    property nbt : Minecraft::NBT::Tag

    def initialize(@x, @y, @z, @type, @nbt); end
  end
end
