require "../../minecraft/nbt"

struct Rosegold::Slot
  property item_id_int : UInt32
  property count : UInt8
  property nbt : Minecraft::NBT::CompoundTag?

  def initialize(@item_id_int = 0, @count = 0, @nbt = nil); end

  def self.read(io) : Rosegold::Slot
    present = io.read_bool
    return new unless present # Empty slot

    item_id_int = io.read_var_int
    count = io.read_byte
    nbt = io.read_nbt
    nbt = nil unless nbt.is_a? Minecraft::NBT::CompoundTag

    new(item_id_int, count, nbt)
  end

  def write(io)
    io.write present?
    return unless present?
    io.write item_id
    io.write_byte count
    io.write nbt || Minecraft::NBT::EndTag.new
  end

  def empty?
    item_id_int <= 0 || count <= 0
  end

  def present?
    !empty?
  end

  def damage
    nbt.try &.["Damage"]?.try &.as_i32
  end

  # Use to get the item_id in new-age string format
  # To get the legacy int format, use `item_id_int`
  def item_id : String
    MCData::MC118.items_by_id_int[item_id_int]?.try &.id_str || raise "Unknown item_id_int: #{item_id_int}"
  end
end
