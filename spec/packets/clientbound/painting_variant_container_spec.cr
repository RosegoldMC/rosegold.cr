require "../../spec_helper"

# Blast-radius regression for issue #338: before the fix, painting/variant was
# read as a plain Holder, so an inline painting variant (which carries width,
# height, asset_id, and optional text) desynced Slot.read and degraded the WHOLE
# SetContainerContent to RawPacket, blanking every slot. Confirm the inline
# painting slot parses and its sibling slots survive.
Spectator.describe "SetContainerContent with painting/variant" do
  before_each { Rosegold::Client.protocol_version = 776_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  def inline_painting : Rosegold::DataComponents::PaintingVariant
    body = Minecraft::IO::Memory.new
    body.write 0_u32             # holder = inline
    body.write 16_u32            # width
    body.write 16_u32            # height
    body.write "minecraft:kebab" # asset_id
    body.write false             # no title
    body.write false             # no author
    Rosegold::DataComponents::PaintingVariant.read(Minecraft::IO::Memory.new(body.to_slice))
  end

  it "parses the painting slot and preserves sibling slots through a full round-trip" do
    plain = Rosegold::WindowSlot.new(0, Rosegold::Slot.new(count: 3_u32, item_id_int: 1_u32))

    painting_slot = Rosegold::Slot.new(
      count: 1_u32,
      item_id_int: 555_u32,
      components_to_add: {
        "painting/variant" => inline_painting.as(Rosegold::DataComponent),
      } of String => Rosegold::DataComponent,
    )
    painting = Rosegold::WindowSlot.new(1, painting_slot)

    trailing = Rosegold::WindowSlot.new(2, Rosegold::Slot.new(count: 5_u32, item_id_int: 9_u32))

    cursor = Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)

    packet = Rosegold::Clientbound::SetContainerContent.new(
      0_u32, 7_u32,
      [plain, painting, trailing] of Rosegold::WindowSlot,
      cursor)

    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte # packet id
    decoded = Rosegold::Clientbound::SetContainerContent.read(io)

    expect(decoded.slots.size).to eq(3)

    expect(decoded.slots[0].as(Rosegold::Slot).item_id_int).to eq(1_u32)
    expect(decoded.slots[0].as(Rosegold::Slot).count).to eq(3_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).item_id_int).to eq(9_u32)
    expect(decoded.slots[2].as(Rosegold::Slot).count).to eq(5_u32)

    painting_decoded = decoded.slots[1].as(Rosegold::Slot)
    expect(painting_decoded.item_id_int).to eq(555_u32)
    component = painting_decoded.components_to_add["painting/variant"].as(Rosegold::DataComponents::PaintingVariant)
    expect(component.raw_bytes.hexstring).to eq(inline_painting.raw_bytes.hexstring)
  end
end
