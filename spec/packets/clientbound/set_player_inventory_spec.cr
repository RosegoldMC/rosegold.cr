require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetPlayerInventory do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SetPlayerInventory[772_u32]).to eq(0x65_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Clientbound::SetPlayerInventory[773_u32]).to eq(0x6A_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Clientbound::SetPlayerInventory[774_u32]).to eq(0x6A_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Clientbound::SetPlayerInventory[775_u32]).to eq(0x6C_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Clientbound::SetPlayerInventory[776_u32]).to eq(0x6C_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Clientbound::SetPlayerInventory.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::SetPlayerInventory.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::SetPlayerInventory.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x65_u8, 772_u32)).to eq(Rosegold::Clientbound::SetPlayerInventory)
  end

  describe "packet parsing" do
    it "reads the raw slot index and the slot" do
      io = Minecraft::IO::Memory.new
      io.write 3_u32 # raw slot index
      io.write 2_u32 # count
      io.write 7_u32 # item_id_int
      io.write 0_u32 # components_to_add count
      io.write 0_u32 # components_to_remove count
      io.pos = 0

      packet = Rosegold::Clientbound::SetPlayerInventory.read(io)

      expect(packet.raw_slot).to eq(3)
      expect(packet.slot.count).to eq(2_u32)
      expect(packet.slot.item_id_int).to eq(7_u32)
    end
  end

  describe "round-trip serialization" do
    it "can write and read a populated slot update" do
      slot = Rosegold::Slot.new(1_u32, 55_u32)
      original_packet = Rosegold::Clientbound::SetPlayerInventory.new(40, slot)

      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)
      io.read_byte # skip packet ID

      read_packet = Rosegold::Clientbound::SetPlayerInventory.read(io)

      expect(read_packet.raw_slot).to eq(40)
      expect(read_packet.slot.item_id_int).to eq(55_u32)
    end
  end

  describe ".menu_index_for" do
    it "maps hotbar raw indices 0-8 to PlayerMenu 36-44" do
      (0..8).each do |raw|
        expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(raw)).to eq(Rosegold::PlayerMenu::HOTBAR_START + raw)
      end
    end

    it "maps main inventory raw indices 9-35 unchanged" do
      (9..35).each do |raw|
        expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(raw)).to eq(raw)
      end
    end

    it "maps armor raw indices 36-39 (boots, leggings, chestplate, helmet order)" do
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(36)).to eq(Rosegold::PlayerMenu::BOOTS_SLOT)
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(37)).to eq(Rosegold::PlayerMenu::LEGGINGS_SLOT)
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(38)).to eq(Rosegold::PlayerMenu::CHESTPLATE_SLOT)
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(39)).to eq(Rosegold::PlayerMenu::HELMET_SLOT)
    end

    it "maps offhand raw index 40 to PlayerMenu OFF_HAND" do
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(40)).to eq(Rosegold::PlayerMenu::OFF_HAND)
    end

    it "has no menu slot for body armor (41) and saddle (42)" do
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(41)).to be_nil
      expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(42)).to be_nil
    end
  end

  describe "callback behavior" do
    let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

    it "assigns a hotbar slot directly into the inventory menu" do
      slot = Rosegold::Slot.new(4_u32, 11_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(0, slot)

      packet.callback(client)

      expect(client.inventory_menu[Rosegold::PlayerMenu::HOTBAR_START].item_id_int).to eq(11_u32)
    end

    it "assigns a main inventory slot directly into the inventory menu" do
      slot = Rosegold::Slot.new(1_u32, 22_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(20, slot)

      packet.callback(client)

      expect(client.inventory_menu[20].item_id_int).to eq(22_u32)
    end

    it "assigns armor slots into the remapped PlayerMenu armor index" do
      slot = Rosegold::Slot.new(1_u32, 33_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(39, slot) # helmet

      packet.callback(client)

      expect(client.inventory_menu.helmet.item_id_int).to eq(33_u32)
    end

    it "assigns the offhand slot" do
      slot = Rosegold::Slot.new(1_u32, 44_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(40, slot)

      packet.callback(client)

      expect(client.inventory_menu.off_hand.item_id_int).to eq(44_u32)
    end

    it "drops body armor (41) and saddle (42) updates without raising" do
      slot = Rosegold::Slot.new(1_u32, 1_u32)

      expect { Rosegold::Clientbound::SetPlayerInventory.new(41, slot).callback(client) }.not_to raise_error
      expect { Rosegold::Clientbound::SetPlayerInventory.new(42, slot).callback(client) }.not_to raise_error
    end
  end
end
