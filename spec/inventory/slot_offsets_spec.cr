require "../spec_helper"

Spectator.describe "Rosegold::SlotOffsets" do
  describe "ContainerMenuOffsets" do
    context "with a 27-slot chest container" do
      let(container_size) { 27 }

      describe ".main_inventory_start_index" do
        it "returns the start of player main inventory" do
          expect(Rosegold::SlotOffsets::ContainerMenuOffsets.main_inventory_start_index(container_size)).to eq(27)
        end
      end

      describe ".hotbar_start_index" do
        it "returns the start of player hotbar" do
          expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_start_index(container_size)).to eq(54)
        end
      end

      describe ".hotbar_slot_index" do
        it "returns correct indices for all hotbar slots" do
          (0...9).each do |hotbar_nr|
            expected = 54 + hotbar_nr
            expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(container_size, hotbar_nr)).to eq(expected)
          end
        end
      end

      describe ".offhand_slot_index" do
        it "returns -1 (not available in container menu)" do
          expect(Rosegold::SlotOffsets::ContainerMenuOffsets.offhand_slot_index(container_size)).to eq(-1)
        end
      end
    end

    context "with a 9-slot dispenser container" do
      let(container_size) { 9 }

      it "calculates offsets correctly for small containers" do
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.main_inventory_start_index(container_size)).to eq(9)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_start_index(container_size)).to eq(36)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(container_size, 0)).to eq(36)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(container_size, 8)).to eq(44)
      end
    end

    context "with a 54-slot large chest container" do
      let(container_size) { 54 }

      it "calculates offsets correctly for large containers" do
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.main_inventory_start_index(container_size)).to eq(54)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_start_index(container_size)).to eq(81)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(container_size, 0)).to eq(81)
        expect(Rosegold::SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(container_size, 8)).to eq(89)
      end
    end
  end

  describe "InventoryMenuOffsets" do
    describe ".main_inventory_start_index" do
      it "returns slot 9 (first main inventory slot)" do
        expect(Rosegold::SlotOffsets::InventoryMenuOffsets.main_inventory_start_index).to eq(9)
      end
    end

    describe ".hotbar_start_index" do
      it "returns slot 36 (first hotbar slot)" do
        expect(Rosegold::SlotOffsets::InventoryMenuOffsets.hotbar_start_index).to eq(36)
      end
    end

    describe ".hotbar_slot_index" do
      it "returns correct indices for all hotbar slots" do
        (0...9).each do |hotbar_nr|
          expected = 36 + hotbar_nr
          expect(Rosegold::SlotOffsets::InventoryMenuOffsets.hotbar_slot_index(hotbar_nr)).to eq(expected)
        end
      end
    end

    describe ".offhand_slot_index" do
      it "returns slot 45 (offhand slot)" do
        expect(Rosegold::SlotOffsets::InventoryMenuOffsets.offhand_slot_index).to eq(45)
      end
    end
  end

  describe "PlayerInventoryOffsets" do
    describe ".main_inventory_to_internal" do
      it "converts main inventory indices to internal indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.main_inventory_to_internal(0)).to eq(9)   # First main slot
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.main_inventory_to_internal(26)).to eq(35) # Last main slot
      end
    end

    describe ".hotbar_to_internal" do
      it "converts hotbar indices to internal indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.hotbar_to_internal(0)).to eq(0) # First hotbar slot
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.hotbar_to_internal(8)).to eq(8) # Last hotbar slot
      end
    end

    describe ".internal_to_main_inventory" do
      it "converts internal indices to main inventory indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_main_inventory(9)).to eq(0)   # First main slot
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_main_inventory(35)).to eq(26) # Last main slot
      end

      it "returns nil for hotbar slots" do
        (0...9).each do |hotbar_index|
          expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_main_inventory(hotbar_index)).to be_nil
        end
      end

      it "returns nil for invalid indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_main_inventory(-1)).to be_nil
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_main_inventory(36)).to be_nil
      end
    end

    describe ".internal_to_hotbar" do
      it "converts internal indices to hotbar indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_hotbar(0)).to eq(0) # First hotbar slot
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_hotbar(8)).to eq(8) # Last hotbar slot
      end

      it "returns nil for main inventory slots" do
        (9...36).each do |main_index|
          expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_hotbar(main_index)).to be_nil
        end
      end

      it "returns nil for invalid indices" do
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_hotbar(-1)).to be_nil
        expect(Rosegold::SlotOffsets::PlayerInventoryOffsets.internal_to_hotbar(36)).to be_nil
      end
    end
  end

  describe "NetworkProtocolOffsets" do
    describe ".network_to_internal" do
      it "converts network main inventory indices to internal indices" do
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(0)).to eq(9)   # Network main slot 0 → Internal main slot 9
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(26)).to eq(35) # Network main slot 26 → Internal main slot 35
      end

      it "converts network hotbar indices to internal indices" do
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(27)).to eq(0) # Network hotbar slot 27 → Internal hotbar slot 0
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(35)).to eq(8) # Network hotbar slot 35 → Internal hotbar slot 8
      end
    end

    describe ".internal_to_network" do
      it "converts internal hotbar indices to network indices" do
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(0)).to eq(27) # Internal hotbar slot 0 → Network hotbar slot 27
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(8)).to eq(35) # Internal hotbar slot 8 → Network hotbar slot 35
      end

      it "converts internal main inventory indices to network indices" do
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(9)).to eq(0)   # Internal main slot 9 → Network main slot 0
        expect(Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(35)).to eq(26) # Internal main slot 35 → Network main slot 26
      end
    end

    describe "round-trip conversion" do
      it "converts network → internal → network correctly" do
        (0...36).each do |network_index|
          internal = Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(network_index)
          back_to_network = Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(internal)
          expect(back_to_network).to eq(network_index)
        end
      end

      it "converts internal → network → internal correctly" do
        (0...36).each do |internal_index|
          network = Rosegold::SlotOffsets::NetworkProtocolOffsets.internal_to_network(internal_index)
          back_to_internal = Rosegold::SlotOffsets::NetworkProtocolOffsets.network_to_internal(network)
          expect(back_to_internal).to eq(internal_index)
        end
      end
    end
  end

  describe "Constants" do
    it "defines correct inventory sizes" do
      expect(Rosegold::SlotOffsets::PLAYER_INVENTORY_SIZE).to eq(36)
      expect(Rosegold::SlotOffsets::HOTBAR_SIZE).to eq(9)
      expect(Rosegold::SlotOffsets::MAIN_INVENTORY_SIZE).to eq(27)
    end

    it "ensures constants add up correctly" do
      expect(Rosegold::SlotOffsets::HOTBAR_SIZE + Rosegold::SlotOffsets::MAIN_INVENTORY_SIZE).to eq(Rosegold::SlotOffsets::PLAYER_INVENTORY_SIZE)
    end
  end
end
