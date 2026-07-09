require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetPlayerInventory do
  it "uses correct packet IDs per protocol" do
    expect(Rosegold::Clientbound::SetPlayerInventory[772_u32]).to eq(0x65_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[774_u32]).to eq(0x6A_u32)
    expect(Rosegold::Clientbound::SetPlayerInventory[775_u32]).to eq(0x6C_u32)
  end

  describe ".player_menu_slot" do
    it "maps hotbar 0-8 to menu slots 36-44" do
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(0_u32)).to eq(36)
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(8_u32)).to eq(44)
    end

    it "passes main inventory 9-35 through unchanged" do
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(9_u32)).to eq(9)
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(35_u32)).to eq(35)
    end

    it "maps armor by EquipmentSlot index, not by visual order" do
      # Vanilla's EQUIPMENT_SLOT_MAPPING: FEET=36, LEGS=37, CHEST=38, HEAD=39
      # rosegold PlayerMenu: HELMET=5, CHESTPLATE=6, LEGGINGS=7, BOOTS=8
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(36_u32)).to eq(8) # FEET → BOOTS
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(37_u32)).to eq(7) # LEGS → LEGGINGS
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(38_u32)).to eq(6) # CHEST → CHESTPLATE
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(39_u32)).to eq(5) # HEAD → HELMET
    end

    it "maps offhand 40 to menu slot 45" do
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(40_u32)).to eq(45)
    end

    it "returns nil for mount-armor slots (BODY/SADDLE)" do
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(41_u32)).to be_nil
      expect(Rosegold::Clientbound::SetPlayerInventory.player_menu_slot(42_u32)).to be_nil
    end
  end

  describe "callback" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    let(:client) do
      Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "spitest"})
    end

    it "writes hotbar updates through to the player inventory" do
      stack = Rosegold::Slot.new(count: 3_u32, item_id_int: 42_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(0_u32, stack)
      packet.callback(client)

      expect(client.player_inventory[0].count).to eq(3_u32)
      expect(client.player_inventory[0].item_id_int).to eq(42_u32)
    end

    it "writes main-inventory updates through to the player inventory" do
      stack = Rosegold::Slot.new(count: 1_u32, item_id_int: 7_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(12_u32, stack)
      packet.callback(client)

      expect(client.player_inventory[12].item_id_int).to eq(7_u32)
    end

    it "writes armor updates to the player menu" do
      stack = Rosegold::Slot.new(count: 1_u32, item_id_int: 99_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(39_u32, stack)
      packet.callback(client)

      expect(client.inventory_menu.helmet.item_id_int).to eq(99_u32)
    end

    it "writes offhand updates to the player menu" do
      stack = Rosegold::Slot.new(count: 1_u32, item_id_int: 55_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(40_u32, stack)
      packet.callback(client)

      expect(client.inventory_menu.off_hand.item_id_int).to eq(55_u32)
    end

    it "silently ignores mount-armor slots" do
      stack = Rosegold::Slot.new(count: 1_u32, item_id_int: 999_u32)
      packet = Rosegold::Clientbound::SetPlayerInventory.new(41_u32, stack)
      expect { packet.callback(client) }.not_to raise_error
    end
  end
end
