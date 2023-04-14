require "../../minecraft/nbt"

class Rosegold::Slot
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
    io.write item_id_int
    io.write_byte count
    io.write nbt || Minecraft::NBT::EndTag.new
  end

  def empty?
    item_id_int <= 0 || count <= 0
  end

  def present?
    !empty?
  end

  def full?
    count >= max_stack_size
  end

  def damage
    nbt.try &.["Damage"]?.try &.as_i32 || 0
  end

  def durability
    max_durability - damage
  end

  def max_durability
    MCData::MC118.items_by_id_int[item_id_int].max_durability || 0_u16
  end

  def max_stack_size
    MCData::MC118.items_by_id_int[item_id_int].stack_size
  end

  def efficiency
    enchantments["efficiency"]? || 0
  end

  def enchantments
    enchantments = Hash(String, Int8 | Int16 | Int32 | Int64 | UInt8).new
    nbt.try &.["Enchantments"]?.try &.as_list.try &.each do |e|
      e = e.as_compound
      id = e["id"].as_s.sub("minecraft:", "")
      enchantments[id] = e["lvl"].as_i
    end
    enchantments
  end

  def enchanted? : Bool
    !enchantments.empty?
  end

  def needs_repair? : Bool
    worth_repairing? && durability < 12
  end

  def worth_repairing? : Bool
    return false unless item_id.includes?("diamond") || item_id.includes?("netherite")

    enchanted? && repair_cost <= 31
  end

  def repair_cost : Int32
    nbt.try &.["RepairCost"]?.try &.as_i32 || 0
  end

  # Use to get the item_id in new-age string format
  # To get the legacy int format, use `item_id_int`
  def item_id : String
    MCData::MC118.items_by_id_int[item_id_int]?.try &.id_str || raise "Unknown item_id_int: #{item_id_int}"
  end

  def matches?(item_id_int : UInt32)
    self.item_id_int == item_id_int
  end

  def matches?(item_id : String)
    self.item_id == item_id
  end

  def matches?(spec : Rosegold::WindowSlot -> _)
    spec.call self
  end

  def matches?(&)
    yield self
  end

  def decrement
    return if count <= 0
    @count -= 1
    make_empty if count <= 0
  end

  def make_empty
    @count = 0
    @item_id_int = 0
    @nbt = nil
  end

  def swap_with(other)
    tmp = @item_id_int
    @item_id_int = other.item_id_int
    other.item_id_int = tmp

    tmp = @count
    @count = other.count
    other.count = tmp

    tmp = @nbt
    @nbt = other.nbt
    other.nbt = tmp
  end

  def to_s(io)
    inspect io
  end
end

class Rosegold::WindowSlot < Rosegold::Slot
  getter slot_nr : Int32

  def initialize(@slot_nr, slot)
    super slot.item_id_int, slot.count, slot.nbt
  end
end
