require "../spec_helper"

Spectator.describe Rosegold::Slot do
  describe "#can_stack_with?" do
    context "when both slots are empty" do
      it "returns false" do
        slot1 = Rosegold::Slot.new
        slot2 = Rosegold::Slot.new
        expect(slot1.can_stack_with?(slot2)).to be_false
      end
    end

    context "when one slot is empty" do
      it "returns false" do
        empty_slot = Rosegold::Slot.new
        stone_slot = Rosegold::Slot.new(25_u32, 1_u32, Hash(UInt32, Rosegold::DataComponent).new, Set(UInt32).new)
        expect(empty_slot.can_stack_with?(stone_slot)).to be_false
        expect(stone_slot.can_stack_with?(empty_slot)).to be_false
      end
    end

    context "when slots have different item types" do
      it "returns false" do
        stone_slot = Rosegold::Slot.new(25_u32, 1_u32, Hash(UInt32, Rosegold::DataComponent).new, Set(UInt32).new)
        dirt_slot = Rosegold::Slot.new(30_u32, 2_u32, Hash(UInt32, Rosegold::DataComponent).new, Set(UInt32).new)
        expect(stone_slot.can_stack_with?(dirt_slot)).to be_false
      end
    end
  end

  describe "#available_stack_space" do
    context "when slot is empty" do
      it "returns max stack size for empty slot" do
        slot = Rosegold::Slot.new
        # Empty slot should have full capacity available  
        # Default max stack size is 64 for most items
        expect(slot.available_stack_space).to eq 64
      end
    end

    context "when slot has partial stack" do
      it "returns remaining space" do
        # Create a slot with 25 items of item ID 1 (stone)
        slot = Rosegold::Slot.new(25_u32, 1_u32, Hash(UInt32, Rosegold::DataComponent).new, Set(UInt32).new)
        # Should have 64 - 25 = 39 space remaining
        expect(slot.available_stack_space).to eq 39
      end
    end
  end
end