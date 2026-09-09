require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetPlayerInventory do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses the packet IDs for all supported protocols" do
    expect(Rosegold::Clientbound::SetPlayerInventory[772_u32]).to eq(0x65_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[773_u32]).to eq(0x6A_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[774_u32]).to eq(0x6A_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[775_u32]).to eq(0x6C_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[776_u32]).to eq(0x6C_u32)
  end

  it "round-trips empty and populated slots for every protocol" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      Rosegold::Client.protocol_version = protocol

      [{0, Rosegold::Slot.new}, {40, Rosegold::Slot.new(5_u32, 99_u32)}].each do |raw_slot, slot|
        bytes = Rosegold::Clientbound::SetPlayerInventory.new(raw_slot, slot).write
        io = Minecraft::IO::Memory.new(bytes)

        expect(io.read_var_int).to eq(Rosegold::Clientbound::SetPlayerInventory[protocol])
        packet = Rosegold::Clientbound::SetPlayerInventory.read(io)
        expect(packet.raw_slot).to eq(raw_slot)
        expect(packet.slot.count).to eq(slot.count)
        expect(packet.slot.item_id_int).to eq(slot.item_id_int)
        expect(io.pos).to eq(bytes.size)
      end
    end
  end

  it "maps raw player inventory slots to PlayerMenu slots" do
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(0)).to eq(Rosegold::PlayerMenu::HOTBAR_START)
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(12)).to eq(12)
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(36)).to eq(Rosegold::PlayerMenu::BOOTS_SLOT)
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(39)).to eq(Rosegold::PlayerMenu::HELMET_SLOT)
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(40)).to eq(Rosegold::PlayerMenu::OFF_HAND)
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(-1)).to be_nil
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(41)).to be_nil
    expect(Rosegold::Clientbound::SetPlayerInventory.menu_index_for(42)).to be_nil
  end

  it "applies hotbar, main, armor, and offhand updates" do
    client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "inventory"})

    Rosegold::Clientbound::SetPlayerInventory.new(0, Rosegold::Slot.new(3_u32, 42_u32)).callback(client)
    Rosegold::Clientbound::SetPlayerInventory.new(12, Rosegold::Slot.new(2_u32, 7_u32)).callback(client)
    Rosegold::Clientbound::SetPlayerInventory.new(39, Rosegold::Slot.new(1_u32, 99_u32)).callback(client)
    Rosegold::Clientbound::SetPlayerInventory.new(40, Rosegold::Slot.new(1_u32, 55_u32)).callback(client)

    expect(client.player_inventory[0].item_id_int).to eq(42_u32)
    expect(client.player_inventory[12].item_id_int).to eq(7_u32)
    expect(client.inventory_menu.helmet.item_id_int).to eq(99_u32)
    expect(client.inventory_menu.off_hand.item_id_int).to eq(55_u32)
  end
end
