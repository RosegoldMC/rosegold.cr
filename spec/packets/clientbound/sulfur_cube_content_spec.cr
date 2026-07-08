require "../../spec_helper"

# sulfur_cube_content (protocol 776 / MC 26.2, component id 78): the absorbed
# block item, encoded as a plain Slot. Before the fix it had no dispatch arm, so
# Slot.read raised UnknownComponentError and degraded the WHOLE container packet
# to RawPacket, blanking every slot. These specs lock in the reader, the write
# round-trip, and that sibling slots survive alongside it.
Spectator.describe Rosegold::DataComponents::SulfurCubeContent do
  before_each { Rosegold::Client.protocol_version = 776_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  # An absorbed block item carrying its own nested component, to exercise a
  # full Slot with a DataComponentPatch (not just bare item_id+count).
  let(:absorbed) do
    Rosegold::Slot.new(
      count: 1_u32,
      item_id_int: 42_u32,
      components_to_add: {
        "damage" => Rosegold::DataComponents::Damage.new(7_u32).as(Rosegold::DataComponent),
      } of String => Rosegold::DataComponent,
      components_to_remove: Set{"repair_cost"},
    )
  end

  it "round-trips the component on its own (read -> write -> read)" do
    original = Rosegold::DataComponents::SulfurCubeContent.new(absorbed)

    buffer = Minecraft::IO::Memory.new
    original.write(buffer)

    decoded = Rosegold::DataComponents::SulfurCubeContent.read(Minecraft::IO::Memory.new(buffer.to_slice))

    expect(decoded.absorbed_block_item.item_id_int).to eq(42_u32)
    expect(decoded.absorbed_block_item.count).to eq(1_u32)
    expect(decoded.absorbed_block_item.components_to_add.keys).to eq(["damage"])
    expect(decoded.absorbed_block_item.components_to_add["damage"].as(Rosegold::DataComponents::Damage).value).to eq(7_u32)
    expect(decoded.absorbed_block_item.components_to_remove.to_a).to eq(["repair_cost"])
  end

  it "encodes as a plain Slot (count-first), round-tripping through Slot.read" do
    buffer = Minecraft::IO::Memory.new
    Rosegold::DataComponents::SulfurCubeContent.new(absorbed).write(buffer)

    via_slot = Rosegold::Slot.read(Minecraft::IO::Memory.new(buffer.to_slice))
    expect(via_slot.count).to eq(1_u32)
    expect(via_slot.item_id_int).to eq(42_u32)
  end

  it "dispatches by name through create_component_by_name" do
    component = Rosegold::DataComponent.create_component_by_name(
      "sulfur_cube_content", 78_u32,
      sulfur_payload_io(absorbed))
    expect(component).to be_a(Rosegold::DataComponents::SulfurCubeContent)
  end
end

# A sulfur slot does not blank its container: parse it inside a SetContainerContent
# alongside ordinary slots and confirm both the component and the siblings survive.
Spectator.describe "SetContainerContent with sulfur_cube_content" do
  before_each { Rosegold::Client.protocol_version = 776_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  it "parses the sulfur slot and preserves sibling slots through a full round-trip" do
    plain = Rosegold::WindowSlot.new(0, Rosegold::Slot.new(count: 3_u32, item_id_int: 1_u32))

    sulfur_inner = Rosegold::Slot.new(count: 1_u32, item_id_int: 100_u32)
    sulfur_slot = Rosegold::Slot.new(
      count: 1_u32,
      item_id_int: 555_u32,
      components_to_add: {
        "sulfur_cube_content" => Rosegold::DataComponents::SulfurCubeContent.new(sulfur_inner).as(Rosegold::DataComponent),
      } of String => Rosegold::DataComponent,
    )
    sulfur = Rosegold::WindowSlot.new(1, sulfur_slot)

    trailing = Rosegold::WindowSlot.new(2, Rosegold::Slot.new(count: 5_u32, item_id_int: 9_u32))

    cursor = Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)

    packet = Rosegold::Clientbound::SetContainerContent.new(
      0_u32, 7_u32,
      [plain, sulfur, trailing] of Rosegold::WindowSlot,
      cursor)

    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte # packet id
    decoded = Rosegold::Clientbound::SetContainerContent.read(io)

    expect(decoded.slots.size).to eq(3)

    # Siblings survive (they would all blank if the sulfur slot degraded the packet).
    expect(decoded.slots[0].as(Rosegold::Slot).item_id_int).to eq(1_u32)
    expect(decoded.slots[0].as(Rosegold::Slot).count).to eq(3_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).item_id_int).to eq(9_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).count).to eq(5_u32)

    # Sulfur slot and its embedded Slot survive.
    sulfur_decoded = decoded.slots[1].as(Rosegold::Slot)
    expect(sulfur_decoded.item_id_int).to eq(555_u32)
    component = sulfur_decoded.components_to_add["sulfur_cube_content"].as(Rosegold::DataComponents::SulfurCubeContent)
    expect(component.absorbed_block_item.item_id_int).to eq(100_u32)
    expect(component.absorbed_block_item.count).to eq(1_u32)
  end
end

private def sulfur_payload_io(absorbed_slot) : Minecraft::IO::Memory
  buffer = Minecraft::IO::Memory.new
  Rosegold::DataComponents::SulfurCubeContent.new(absorbed_slot).write(buffer)
  Minecraft::IO::Memory.new(buffer.to_slice)
end
