require "../../spec_helper"

# M8 blast-radius (issue #338): a can_break item carrying a non-empty partial
# predicate map used to raise inside Slot.read, degrading the WHOLE
# SetContainerContent to RawPacket and blanking every slot. BlockPredicates.write
# is a lossy stub (emits an empty predicate list), so we hand-build the offending
# slot's wire bytes to exercise the reader, then confirm siblings survive.
Spectator.describe "SetContainerContent with a can_break partial predicate" do
  before_each { Rosegold::Client.protocol_version = 774_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  def write_unnamed_nbt(io, tag)
    io.write_byte tag.tag_type
    tag.write io
  end

  def write_can_break_slot(buffer)
    buffer.write 1_u32   # count
    buffer.write 555_u32 # item id
    buffer.write 1_u32   # components-to-add count
    buffer.write 0_u32   # components-to-remove count
    can_break_id = Rosegold::DataComponentTypes.id_for("can_break", 774_u32) || raise "no can_break id"
    buffer.write can_break_id
    # BlockPredicates value:
    buffer.write 1_u32 # predicate count
    buffer.write false # has_blocks
    buffer.write false # has_properties
    buffer.write false # has_nbt
    buffer.write 0_u32 # exact matcher count
    buffer.write 1_u32 # partial matcher count
    buffer.write true  # Either: predicate-type registry
    buffer.write 0_u32 # type registry id
    write_unnamed_nbt(buffer, Minecraft::NBT::CompoundTag.new(
      {"min" => Minecraft::NBT::IntTag.new(5).as(Minecraft::NBT::Tag)} of String => Minecraft::NBT::Tag
    ))
  end

  it "parses the offending slot and preserves sibling slots" do
    buffer = Minecraft::IO::Memory.new
    buffer.write 0_u32 # window_id
    buffer.write 7_u32 # state_id
    buffer.write 3_u32 # slot count
    Rosegold::Slot.new(count: 3_u32, item_id_int: 1_u32).write(buffer)
    write_can_break_slot(buffer)
    Rosegold::Slot.new(count: 5_u32, item_id_int: 9_u32).write(buffer)
    Rosegold::Slot.new.write(buffer) # cursor

    io = Minecraft::IO::Memory.new(buffer.to_slice)
    decoded = Rosegold::Clientbound::SetContainerContent.read(io)

    expect(decoded.slots.size).to eq(3)
    expect(decoded.slots[0].as(Rosegold::Slot).item_id_int).to eq(1_u32)
    expect(decoded.slots[0].as(Rosegold::Slot).count).to eq(3_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).item_id_int).to eq(9_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).count).to eq(5_u32)

    offending = decoded.slots[1].as(Rosegold::Slot)
    expect(offending.item_id_int).to eq(555_u32)
    expect(offending.components_to_add.keys).to contain("can_break")
  end
end
