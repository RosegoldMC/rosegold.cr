require "../spec_helper"

private def test_client
  Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "handletest"})
end

private def make_slot(item_id : UInt32, count : UInt32 = 1_u32) : Rosegold::Slot
  Rosegold::Slot.new(count: count, item_id_int: item_id)
end

Spectator.describe Rosegold::ContainerHandle do
  let(:client) { test_client }
  let(:menu) { Rosegold::ChestMenu.new(client, 1_u8, Rosegold::Chat.new("Test Chest"), rows: 3) }
  let(:handle) { Rosegold::ContainerHandle.new(client, menu) }

  describe "#count_in_container" do
    it "returns 0 when container is empty" do
      expect(handle.count_in_container(1_u32)).to eq 0
    end

    it "counts matching items in container slots" do
      menu[0] = make_slot(10_u32, 5_u32)
      menu[1] = make_slot(10_u32, 3_u32)
      menu[2] = make_slot(20_u32, 7_u32)
      expect(handle.count_in_container(10_u32)).to eq 8
    end

    it "ignores non-matching items" do
      menu[0] = make_slot(10_u32, 5_u32)
      expect(handle.count_in_container(99_u32)).to eq 0
    end

    it "does not count items in player inventory" do
      # Container has 27 slots (3 rows * 9), player inventory starts at 27
      menu[27] = make_slot(10_u32, 10_u32) # player inventory slot
      expect(handle.count_in_container(10_u32)).to eq 0
    end
  end

  describe "#count_in_player" do
    it "returns 0 when player inventory is empty" do
      expect(handle.count_in_player(1_u32)).to eq 0
    end

    it "counts matching items in player inventory and hotbar" do
      # Player inventory starts at slot 27 for a 3-row chest
      menu[27] = make_slot(10_u32, 4_u32) # main inventory
      menu[54] = make_slot(10_u32, 6_u32) # hotbar (27 + 27 = 54)
      expect(handle.count_in_player(10_u32)).to eq 10
    end

    it "does not count items in container" do
      menu[0] = make_slot(10_u32, 10_u32) # container slot
      expect(handle.count_in_player(10_u32)).to eq 0
    end

    it "ignores non-matching items in player inventory" do
      menu[27] = make_slot(20_u32, 5_u32)
      expect(handle.count_in_player(10_u32)).to eq 0
    end
  end

  describe "#find_in_container" do
    it "returns nil when container is empty" do
      expect(handle.find_in_container(10_u32)).to be_nil
    end

    it "returns the first matching slot" do
      menu[2] = make_slot(10_u32, 3_u32)
      menu[5] = make_slot(10_u32, 7_u32)
      result = handle.find_in_container(10_u32)
      expect(result).not_to be_nil
      if result
        expect(result.slot_number).to eq 2
        expect(result.count).to eq 3_u32
      end
    end

    it "returns nil for non-matching items" do
      menu[0] = make_slot(20_u32, 1_u32)
      expect(handle.find_in_container(10_u32)).to be_nil
    end

    it "does not find items in player inventory" do
      menu[27] = make_slot(10_u32, 5_u32)
      expect(handle.find_in_container(10_u32)).to be_nil
    end
  end

  describe "#find_in_inventory" do
    it "returns nil when player inventory is empty" do
      expect(handle.find_in_inventory(10_u32)).to be_nil
    end

    it "finds items in main inventory" do
      menu[27] = make_slot(10_u32, 3_u32)
      result = handle.find_in_inventory(10_u32)
      expect(result).not_to be_nil
      if result
        expect(result.slot_number).to eq 27
      end
    end

    it "finds items in hotbar" do
      menu[54] = make_slot(10_u32, 3_u32)
      result = handle.find_in_inventory(10_u32)
      expect(result).not_to be_nil
      if result
        expect(result.slot_number).to eq 54
      end
    end

    it "does not find items in container" do
      menu[0] = make_slot(10_u32, 5_u32)
      expect(handle.find_in_inventory(10_u32)).to be_nil
    end
  end

  describe "typed menu access" do
    it "#as_chest returns ChestMenu for a chest" do
      result = handle.as_chest
      expect(result).not_to be_nil
      expect(result).to be_a(Rosegold::ChestMenu)
    end

    it "#as_furnace returns nil for a chest" do
      expect(handle.as_furnace).to be_nil
    end

    it "#as_anvil returns nil for a chest" do
      expect(handle.as_anvil).to be_nil
    end

    it "#as_hopper returns nil for a chest" do
      expect(handle.as_hopper).to be_nil
    end

    it "#as_crafting returns nil for a chest" do
      expect(handle.as_crafting).to be_nil
    end

    it "#as_brewing_stand returns nil for a chest" do
      expect(handle.as_brewing_stand).to be_nil
    end

    it "#as_enchantment returns nil for a chest" do
      expect(handle.as_enchantment).to be_nil
    end

    it "#as_merchant returns nil for a chest" do
      expect(handle.as_merchant).to be_nil
    end

    context "with a furnace menu" do
      let(:furnace_menu) { Rosegold::FurnaceMenu.new(client, 2_u8, Rosegold::Chat.new("Test Furnace")) }
      let(:furnace_handle) { Rosegold::ContainerHandle.new(client, furnace_menu) }

      it "#as_furnace returns FurnaceMenu" do
        result = furnace_handle.as_furnace
        expect(result).not_to be_nil
        expect(result).to be_a(Rosegold::FurnaceMenu)
      end

      it "#as_chest returns nil" do
        expect(furnace_handle.as_chest).to be_nil
      end
    end

    context "with a hopper menu" do
      let(:hopper_menu) { Rosegold::HopperMenu.new(client, 3_u8, Rosegold::Chat.new("Test Hopper")) }
      let(:hopper_handle) { Rosegold::ContainerHandle.new(client, hopper_menu) }

      it "#as_hopper returns HopperMenu" do
        result = hopper_handle.as_hopper
        expect(result).not_to be_nil
        expect(result).to be_a(Rosegold::HopperMenu)
      end

      it "#as_chest returns nil" do
        expect(hopper_handle.as_chest).to be_nil
      end
    end
  end

  describe "#menu" do
    it "exposes the underlying menu" do
      expect(handle.menu).to be menu
    end
  end
end
