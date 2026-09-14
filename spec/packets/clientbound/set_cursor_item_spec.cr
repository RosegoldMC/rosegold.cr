require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetCursorItem do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses the packet IDs for all supported protocols" do
    expect(Rosegold::Clientbound::SetCursorItem[772_u32]).to eq(0x59_u32)
    expect(Rosegold::Clientbound::SetCursorItem[773_u32]).to eq(0x5E_u32)
    expect(Rosegold::Clientbound::SetCursorItem[774_u32]).to eq(0x5E_u32)
    expect(Rosegold::Clientbound::SetCursorItem[775_u32]).to eq(0x60_u32)
    expect(Rosegold::Clientbound::SetCursorItem[776_u32]).to eq(0x60_u32)
  end

  it "round-trips empty and populated slots for every protocol" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      Rosegold::Client.protocol_version = protocol

      [Rosegold::Slot.new, Rosegold::Slot.new(5_u32, 99_u32)].each do |slot|
        bytes = Rosegold::Clientbound::SetCursorItem.new(slot).write
        io = Minecraft::IO::Memory.new(bytes)

        expect(io.read_var_int).to eq(Rosegold::Clientbound::SetCursorItem[protocol])
        packet = Rosegold::Clientbound::SetCursorItem.read(io)
        expect(packet.slot.count).to eq(slot.count)
        expect(packet.slot.item_id_int).to eq(slot.item_id_int)
        expect(io.pos).to eq(bytes.size)
      end
    end
  end

  it "applies a server cursor correction to empty" do
    client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "cursor"})
    menu = client.container_menu
    menu.cursor = Rosegold::Slot.new(1_u32, 42_u32)

    Rosegold::Clientbound::SetCursorItem.new(Rosegold::Slot.new).callback(client)

    expect(menu.cursor.empty?).to be_true
    expect { menu.check_and_fix_desync }.not_to raise_error
  end
end
