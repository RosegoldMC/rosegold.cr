require "../../minecraft/nbt"

struct Rosegold::Slot
  property item_id_int : UInt32
  property count : UInt8
  property nbt : Minecraft::NBT::Tag?

  def initialize(@item_id_int = 0, @count = 0, @nbt = nil); end

  def self.read(io : IO) : Rosegold::Slot
    present = io.read_bool
    return new unless present # Empty slot

    item_id_int = io.read_var_int
    count = io.read_byte
    nbt = io.read_nbt
    nbt = nil if nbt.is_a? Minecraft::NBT::EndTag

    new(item_id_int, count, nbt)
  end

  def empty?
    item_id <= 0 || count <= 0
  end

  # Use to get the item_id in new-age string format
  # To get the legacy int format, use `item_id_int`
  def item_id : String
    MCData::MC118.items_by_id_int[item_id_int]?.try &.id_str || raise "Unknown item_id_int: #{item_id_int}"
  end
end
