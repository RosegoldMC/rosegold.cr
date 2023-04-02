require "../../minecraft/nbt"

struct Rosegold::Slot
  property item_id : UInt32
  property count : UInt8
  property nbt : Minecraft::NBT::Tag?

  def initialize(@item_id = 0, @count = 0, @nbt = nil); end

  def self.read(io : IO) : Rosegold::Slot
    present = io.read_bool
    return new unless present # Empty slot

    item_id = io.read_var_int
    count = io.read_byte
    nbt = Minecraft::NBT::Tag.read_named(io)[1]
    nbt = nil if nbt.is_a? Minecraft::NBT::EndTag

    new(item_id, count, nbt)
  end

  def empty?
    item_id <= 0 || count <= 0
  end
end
