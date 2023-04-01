struct Rosegold::Slot
  property item_id : UInt16
  property count : UInt8
  property nbt : Minecraft::NBT::Tag?

  def initialize(@item_id = 0, @count = 0, @nbt = nil); end

  def empty?
    item_id <= 0 || count <= 0
  end
end
