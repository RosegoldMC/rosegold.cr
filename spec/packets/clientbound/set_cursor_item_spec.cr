require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetCursorItem do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SetCursorItem[772_u32]).to eq(0x59_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Clientbound::SetCursorItem[773_u32]).to eq(0x5E_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Clientbound::SetCursorItem[774_u32]).to eq(0x5E_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Clientbound::SetCursorItem[775_u32]).to eq(0x60_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Clientbound::SetCursorItem[776_u32]).to eq(0x60_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Clientbound::SetCursorItem.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::SetCursorItem.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::SetCursorItem.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x59_u8, 772_u32)).to eq(Rosegold::Clientbound::SetCursorItem)
  end

  describe "packet parsing" do
    it "reads an empty slot" do
      io = Minecraft::IO::Memory.new
      io.write 0_u32 # empty slot count
      io.pos = 0

      packet = Rosegold::Clientbound::SetCursorItem.read(io)

      expect(packet.slot.empty?).to be_true
    end

    it "reads a populated slot" do
      io = Minecraft::IO::Memory.new
      io.write 5_u32 # count
      io.write 1_u32 # item_id_int
      io.write 0_u32 # components_to_add count
      io.write 0_u32 # components_to_remove count
      io.pos = 0

      packet = Rosegold::Clientbound::SetCursorItem.read(io)

      expect(packet.slot.count).to eq(5_u32)
      expect(packet.slot.item_id_int).to eq(1_u32)
    end
  end

  describe "round-trip serialization" do
    it "can write and read an empty cursor slot" do
      original_packet = Rosegold::Clientbound::SetCursorItem.new(Rosegold::Slot.new)

      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)
      io.read_byte # skip packet ID

      read_packet = Rosegold::Clientbound::SetCursorItem.read(io)

      expect(read_packet.slot.empty?).to be_true
    end

    it "can write and read a populated cursor slot" do
      slot = Rosegold::Slot.new(3_u32, 42_u32)
      original_packet = Rosegold::Clientbound::SetCursorItem.new(slot)

      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)
      io.read_byte # skip packet ID

      read_packet = Rosegold::Clientbound::SetCursorItem.read(io)

      expect(read_packet.slot.count).to eq(3_u32)
      expect(read_packet.slot.item_id_int).to eq(42_u32)
    end
  end

  describe "callback behavior" do
    let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

    it "sets the cursor slot on the client's active container menu" do
      slot = Rosegold::Slot.new(7_u32, 99_u32)
      packet = Rosegold::Clientbound::SetCursorItem.new(slot)

      packet.callback(client)

      expect(client.container_menu.cursor.count).to eq(7_u32)
      expect(client.container_menu.cursor.item_id_int).to eq(99_u32)
    end

    it "defaults to the inventory menu when no container is open" do
      slot = Rosegold::Slot.new(1_u32, 5_u32)
      packet = Rosegold::Clientbound::SetCursorItem.new(slot)

      packet.callback(client)

      expect(client.inventory_menu.cursor.count).to eq(1_u32)
    end
  end
end
