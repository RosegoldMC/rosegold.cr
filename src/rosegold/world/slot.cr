require "../../minecraft/nbt"

struct Rosegold::Slot
  property item_id : UInt32
  property count : UInt8
  property nbt : Minecraft::NBT::CompoundTag?

  def initialize(@item_id = 0, @count = 0, @nbt = nil); end

  def self.read(io) : Rosegold::Slot
    present = io.read_bool
    return new unless present # Empty slot

    item_id = io.read_var_int
    count = io.read_byte
    nbt = io.read_nbt
    nbt = nil unless nbt.is_a? Minecraft::NBT::CompoundTag

    new(item_id, count, nbt)
  end

  def write(io)
    io.write present?
    return unless present?
    io.write item_id
    io.write_byte count
    io.write nbt || Minecraft::NBT::EndTag.new
  end

  def empty?
    item_id <= 0 || count <= 0
  end

  def present?
    !empty?
  end
end
