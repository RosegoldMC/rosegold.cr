require "../../minecraft/nbt"

struct Rosegold::Slot
  property item_id : UInt32
  property count : UInt8
  property nbt : Minecraft::NBT::Tag?

  def initialize(@item_id = 0, @count = 0, @nbt = nil); end

  def self.read(io : IO) : Rosegold::Slot
    present = io.read_bool

    if present
      item_id = io.read_var_int
      count = io.read_byte

      # Check if there's any NBT data
      first_byte = io.peek
      if first_byte == 0
        io.read_byte # Skip the TAG_END byte
        nbt = nil
      else
        nbt = Minecraft::NBT::Tag.read(io)
      end

      new(item_id, count, nbt)
    else
      new # Empty slot
    end
  end

  def empty?
    item_id <= 0 || count <= 0
  end
end
