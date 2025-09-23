require "../../minecraft/nbt"
require "./paletted_container"
require "./section"

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
    section_index = (y - min_y) >> 4
    section = sections[section_index]? || return nil
    index = (((y - min_y) & 15) << 8) | (z << 4) | x
    section.block_state index.to_u32
  end

  def set_block_state(x : Int32, y : Int32, z : Int32, block_state : BlockStateNr) : BlockStateNr?
    x, z = x & 15, z & 15
    section_index = (y - min_y) >> 4
    return nil if section_index < 0 || section_index >= sections.size
    section = sections[section_index]

    # Java client optimization: if setting air to air in an air-only section, return nil
    if section.has_only_air? && block_state == 0_u16
      return nil
    end

    index = (((y - min_y) & 15) << 8) | (z << 4) | x
    previous_state = section.set_block_state index.to_u32, block_state

    # Return nil if no change occurred (matching Java behavior)
    return nil if previous_state == block_state

    previous_state
  end

  struct BlockEntity
    property x : Int32, y : Int32, z : Int32
    property type : UInt32
    property nbt : Minecraft::NBT::Tag

    def initialize(@x, @y, @z, @type, @nbt); end
  end
end
