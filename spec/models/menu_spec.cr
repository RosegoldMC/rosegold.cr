require "../spec_helper"

# Helper to create a test client (not connected, just for initialization)
private def test_client
  Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "menutest"})
end

# Helper to create a non-empty slot with a given item ID and count
private def make_slot(item_id : UInt32, count : UInt32 = 1_u32) : Rosegold::Slot
  Rosegold::Slot.new(count: count, item_id_int: item_id)
end

# Helper to create a slot with custom components
private def make_slot_with_components(item_id : UInt32, count : UInt32, components : Hash(String, Rosegold::DataComponent)) : Rosegold::Slot
  Rosegold::Slot.new(count: count, item_id_int: item_id, components_to_add: components)
end

Spectator.describe Rosegold::PlayerMenu do
  let(:client) { test_client }
  let(:menu) { Rosegold::PlayerMenu.new(client) }

  describe "basic properties" do
    it "has menu_id 0" do
      expect(menu.menu_id).to eq 0_u8
    end

    it "has 46 total slots" do
      expect(menu.total_slots).to eq 46
    end

    it "has player_inventory_start at 9" do
      expect(menu.player_inventory_start).to eq 9
    end

    it "has offhand_slot_index at 45" do
      expect(menu.offhand_slot_index).to eq 45
    end
  end

  describe "slot access" do
    it "starts with all empty slots" do
      46.times do |i|
        expect(menu[i].empty?).to be_true
      end
    end

    it "can set and get crafting result slot (0)" do
      slot = make_slot(1_u32, 1_u32)
      menu[0] = slot
      expect(menu[0].item_id_int).to eq 1_u32
    end

    it "can set and get crafting slots (1-4)" do
      slot = make_slot(2_u32, 3_u32)
      menu[2] = slot
      expect(menu[2].item_id_int).to eq 2_u32
      expect(menu[2].count).to eq 3_u32
    end

    it "can set and get armor slots (5-8)" do
      slot = make_slot(3_u32, 1_u32)
      menu[5] = slot
      expect(menu[5].item_id_int).to eq 3_u32
    end

    it "can set and get main inventory slots (9-35)" do
      slot = make_slot(4_u32, 10_u32)
      menu[9] = slot
      expect(menu[9].item_id_int).to eq 4_u32
      expect(menu[9].count).to eq 10_u32
    end

    it "can set and get hotbar slots (36-44)" do
      slot = make_slot(5_u32, 5_u32)
      menu[36] = slot
      expect(menu[36].item_id_int).to eq 5_u32
    end

    it "can set and get offhand slot (45)" do
      slot = make_slot(6_u32, 1_u32)
      menu[45] = slot
      expect(menu[45].item_id_int).to eq 6_u32
    end

    it "raises for invalid slot index" do
      expect { menu[46] }.to raise_error(ArgumentError)
      expect { menu[-1] }.to raise_error(ArgumentError)
    end
  end

  describe "#same_item_same_components?" do
    it "returns true for slots with same item and no components" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(10_u32, 3_u32)
      expect(menu.same_item_same_components?(slot1, slot2)).to be_true
    end

    it "returns false for different item IDs" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(20_u32, 5_u32)
      expect(menu.same_item_same_components?(slot1, slot2)).to be_false
    end

    it "returns false if either slot is empty" do
      empty = Rosegold::Slot.new
      non_empty = make_slot(10_u32, 5_u32)
      expect(menu.same_item_same_components?(empty, non_empty)).to be_false
      expect(menu.same_item_same_components?(non_empty, empty)).to be_false
      expect(menu.same_item_same_components?(empty, empty)).to be_false
    end

    it "returns false for same item with different components" do
      comp1 = Hash(String, Rosegold::DataComponent).new
      comp1["max_stack_size"] = Rosegold::DataComponents::MaxStackSize.new(16_u32)
      slot1 = make_slot_with_components(10_u32, 5_u32, comp1)

      comp2 = Hash(String, Rosegold::DataComponent).new
      comp2["max_stack_size"] = Rosegold::DataComponents::MaxStackSize.new(32_u32)
      slot2 = make_slot_with_components(10_u32, 5_u32, comp2)

      expect(menu.same_item_same_components?(slot1, slot2)).to be_false
    end

    it "returns true for same item with same component objects" do
      comp = Rosegold::DataComponents::MaxStackSize.new(16_u32)
      comp1 = Hash(String, Rosegold::DataComponent).new
      comp1["max_stack_size"] = comp
      slot1 = make_slot_with_components(10_u32, 5_u32, comp1)

      comp2 = Hash(String, Rosegold::DataComponent).new
      comp2["max_stack_size"] = comp
      slot2 = make_slot_with_components(10_u32, 3_u32, comp2)

      expect(menu.same_item_same_components?(slot1, slot2)).to be_true
    end
  end

  describe "#copy_slot" do
    it "creates an independent copy" do
      original = make_slot(10_u32, 5_u32)
      copy = menu.copy_slot(original)
      expect(copy.item_id_int).to eq original.item_id_int
      expect(copy.count).to eq original.count

      copy.count = 99_u32
      expect(original.count).to eq 5_u32
    end

    it "copies components independently" do
      comp = Hash(String, Rosegold::DataComponent).new
      comp["max_stack_size"] = Rosegold::DataComponents::MaxStackSize.new(16_u32)
      original = make_slot_with_components(10_u32, 5_u32, comp)

      copy = menu.copy_slot(original)
      expect(copy.components_to_add.size).to eq 1
    end
  end

  describe "#slots_match?" do
    it "returns true for two empty slots" do
      empty1 = Rosegold::Slot.new
      empty2 = Rosegold::Slot.new
      expect(menu.slots_match?(empty1, empty2)).to be_true
    end

    it "returns false when one is empty and other is not" do
      empty = Rosegold::Slot.new
      non_empty = make_slot(10_u32, 5_u32)
      expect(menu.slots_match?(empty, non_empty)).to be_false
      expect(menu.slots_match?(non_empty, empty)).to be_false
    end

    it "returns true for identical non-empty slots" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(10_u32, 5_u32)
      expect(menu.slots_match?(slot1, slot2)).to be_true
    end

    it "returns false for same item different count" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(10_u32, 3_u32)
      expect(menu.slots_match?(slot1, slot2)).to be_false
    end

    it "returns false for different items same count" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(20_u32, 5_u32)
      expect(menu.slots_match?(slot1, slot2)).to be_false
    end
  end

  describe "#can_stack?" do
    it "returns false if either slot is empty" do
      empty = Rosegold::Slot.new
      non_empty = make_slot(10_u32, 5_u32)
      expect(menu.can_stack?(empty, non_empty)).to be_false
      expect(menu.can_stack?(non_empty, empty)).to be_false
    end

    it "returns false for different items" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(20_u32, 5_u32)
      expect(menu.can_stack?(slot1, slot2)).to be_false
    end

    it "returns true for same items within stack limit" do
      slot1 = make_slot(10_u32, 5_u32)
      slot2 = make_slot(10_u32, 5_u32)
      expect(menu.can_stack?(slot1, slot2)).to be_true
    end

    it "returns false for same items exceeding stack limit" do
      slot1 = make_slot(10_u32, 50_u32)
      slot2 = make_slot(10_u32, 50_u32)
      expect(menu.can_stack?(slot1, slot2)).to be_false
    end

    it "returns false for same item with different components" do
      comp1 = Hash(String, Rosegold::DataComponent).new
      comp1["max_stack_size"] = Rosegold::DataComponents::MaxStackSize.new(16_u32)
      slot1 = make_slot_with_components(10_u32, 5_u32, comp1)
      slot2 = make_slot(10_u32, 5_u32)
      expect(menu.can_stack?(slot1, slot2)).to be_false
    end
  end

  describe "#safe_insert" do
    it "places cursor into empty target slot" do
      cursor = make_slot(10_u32, 5_u32)
      menu[9] = Rosegold::Slot.new

      result = menu.safe_insert(9, cursor, 5)
      expect(result.empty?).to be_true
      expect(menu[9].item_id_int).to eq 10_u32
      expect(menu[9].count).to eq 5_u32
    end

    it "places partial amount into empty target slot" do
      cursor = make_slot(10_u32, 10_u32)
      menu[9] = Rosegold::Slot.new

      result = menu.safe_insert(9, cursor, 3)
      expect(result.count).to eq 7_u32
      expect(menu[9].count).to eq 3_u32
    end

    it "merges with existing matching stack" do
      menu[9] = make_slot(10_u32, 3_u32)
      cursor = make_slot(10_u32, 5_u32)

      result = menu.safe_insert(9, cursor, 5)
      expect(result.empty?).to be_true
      expect(menu[9].count).to eq 8_u32
    end

    it "returns cursor unchanged for non-matching items" do
      menu[9] = make_slot(20_u32, 3_u32)
      cursor = make_slot(10_u32, 5_u32)

      result = menu.safe_insert(9, cursor, 5)
      expect(result.count).to eq 5_u32
      expect(menu[9].item_id_int).to eq 20_u32
    end

    it "returns cursor unchanged for empty cursor" do
      result = menu.safe_insert(9, Rosegold::Slot.new, 1)
      expect(result.empty?).to be_true
    end

    it "respects may_place? restrictions (crafting result)" do
      cursor = make_slot(10_u32, 5_u32)
      result = menu.safe_insert(0, cursor, 5)
      expect(result.count).to eq 5_u32
      expect(menu[0].empty?).to be_true
    end
  end

  describe "#safe_take" do
    it "takes full stack from a slot" do
      menu[9] = make_slot(10_u32, 5_u32)
      result = menu.safe_take(9, 5)
      expect(result).not_to be_nil
      if result
        expect(result[:taken].count).to eq 5_u32
        expect(result[:remaining_slot].empty?).to be_true
      end
    end

    it "takes partial stack from a slot" do
      menu[9] = make_slot(10_u32, 10_u32)
      result = menu.safe_take(9, 3)
      expect(result).not_to be_nil
      if result
        expect(result[:taken].count).to eq 3_u32
        expect(result[:remaining_slot].count).to eq 7_u32
      end
    end

    it "returns nil for empty slot" do
      result = menu.safe_take(9, 1)
      expect(result).to be_nil
    end

    it "clamps take amount to available count" do
      menu[9] = make_slot(10_u32, 3_u32)
      result = menu.safe_take(9, 100)
      expect(result).not_to be_nil
      if result
        expect(result[:taken].count).to eq 3_u32
      end
    end
  end

  describe "#move_item_stack_to" do
    it "moves items to first empty slot in range" do
      menu[9] = make_slot(10_u32, 5_u32)
      moved = menu.move_item_stack_to(9, 36, 45)
      expect(moved).to be_true
      expect(menu[9].empty?).to be_true
      expect(menu[36].item_id_int).to eq 10_u32
      expect(menu[36].count).to eq 5_u32
    end

    it "merges with existing matching stack first" do
      menu[9] = make_slot(10_u32, 5_u32)
      menu[36] = make_slot(10_u32, 3_u32)
      moved = menu.move_item_stack_to(9, 36, 45)
      expect(moved).to be_true
      expect(menu[9].empty?).to be_true
      expect(menu[36].count).to eq 8_u32
    end

    it "returns false for empty source" do
      moved = menu.move_item_stack_to(9, 36, 45)
      expect(moved).to be_false
    end

    it "places in empty slot when no matching stacks exist" do
      menu[9] = make_slot(10_u32, 5_u32)
      menu[36] = make_slot(20_u32, 3_u32)
      moved = menu.move_item_stack_to(9, 36, 45)
      expect(moved).to be_true
      expect(menu[9].empty?).to be_true
      expect(menu[37].item_id_int).to eq 10_u32
    end

    it "moves in reverse when specified" do
      menu[9] = make_slot(10_u32, 5_u32)
      moved = menu.move_item_stack_to(9, 36, 45, reverse: true)
      expect(moved).to be_true
      expect(menu[9].empty?).to be_true
      expect(menu[44].item_id_int).to eq 10_u32
    end
  end

  describe "#hotbar_slot_index" do
    it "maps hotbar number to correct window slot" do
      9.times do |i|
        expect(menu.hotbar_slot_index(i)).to eq 36 + i
      end
    end
  end

  describe "cursor management" do
    it "starts with empty cursor" do
      expect(menu.cursor.empty?).to be_true
    end

    it "can set and get cursor" do
      slot = make_slot(10_u32, 5_u32)
      menu.cursor = slot
      expect(menu.cursor.item_id_int).to eq 10_u32
      expect(menu.cursor.count).to eq 5_u32
    end
  end

  describe "#may_place?" do
    it "disallows placing in crafting result slot" do
      slot = make_slot(10_u32, 1_u32)
      expect(menu.may_place?(0, slot)).to be_false
    end

    it "allows placing in main inventory slots" do
      slot = make_slot(10_u32, 1_u32)
      expect(menu.may_place?(9, slot)).to be_true
    end

    it "allows placing in hotbar slots" do
      slot = make_slot(10_u32, 1_u32)
      expect(menu.may_place?(36, slot)).to be_true
    end

    it "allows placing in offhand slot" do
      slot = make_slot(10_u32, 1_u32)
      expect(menu.may_place?(45, slot)).to be_true
    end

    it "disallows placing empty slot" do
      expect(menu.may_place?(9, Rosegold::Slot.new)).to be_false
    end
  end
end

# ============================================================================
# Bug regression tests — each test should FAIL with current code, PASS after fix
# ============================================================================

# Test menu that overrides get_slot_max_stack_size to return a small limit,
# simulating items like ender pearls (max 16).
class SmallStackMenu < Rosegold::ContainerMenu
  def initialize(client : Rosegold::Client)
    super(client, 1_u8, Rosegold::Chat.new("SmallStack"), 9)
  end

  def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    16
  end
end

# Test menu that overrides may_pickup? to block pickup from specific slots.
class NoPickupMenu < Rosegold::ContainerMenu
  def initialize(client : Rosegold::Client)
    super(client, 1_u8, Rosegold::Chat.new("NoPickup"), 9)
  end

  def may_pickup?(slot_index : Int32) : Bool
    slot_index != 0
  end
end

Spectator.describe "Bug: move_item_stack_to Phase 2 ignores slot max stack size" do
  let(:client) { test_client }
  let(:menu) { SmallStackMenu.new(client) }

  it "places into first empty slot and breaks (vanilla behavior)" do
    # Place 32 items in container slot 0. Slot max is 16.
    # Vanilla Phase 2 places up to max in first empty slot, then breaks.
    # The outer perform_shift_click loop handles the rest.
    menu[0] = make_slot(100_u32, 32_u32)

    # Slots 1-8 are empty container slots. Move from 0 into range 1..9
    menu.move_item_stack_to(0, 1, 9)

    # Slot 1 gets 16 (max), remaining 16 stays in slot 0
    expect(menu[0].count).to eq 16_u32
    expect(menu[1].count).to eq 16_u32
    expect(menu[2].empty?).to be_true
  end
end

Spectator.describe "Bug: FurnaceMenu shift-click priority reversed" do
  let(:client) { test_client }
  let(:menu) { Rosegold::FurnaceMenu.new(client, 1_u8, Rosegold::Chat.new("Furnace")) }

  it "routes player inventory items to ingredient slot before fuel slot" do
    # FurnaceMenu container_size = 3, so player inventory starts at index 3.
    # Slot 3 = first main inventory slot in the furnace window.
    # Both ingredient (0) and fuel (1) are empty.
    # Vanilla: tries ingredient (0) first, then fuel (1).
    # Current code: tries fuel (1) first due to reversed order.
    menu[3] = make_slot(100_u32, 1_u32)
    menu.quick_move_stack(3)

    # After fix: item should be in ingredient slot (0), not fuel slot (1)
    expect(menu[0].count).to eq 1_u32
    expect(menu[0].item_id_int).to eq 100_u32
    expect(menu[1].empty?).to be_true
  end
end

Spectator.describe "Bug: perform_shift_click missing may_pickup? check" do
  let(:client) { test_client }
  let(:menu) { NoPickupMenu.new(client) }

  it "does not move items from a slot where may_pickup? returns false" do
    # Slot 0 has may_pickup? = false. Put items there.
    # perform_shift_click should be a no-op.
    # Current code: moves items anyway because it never checks may_pickup?.
    menu[0] = make_slot(100_u32, 5_u32)
    menu.perform_shift_click(0)

    # After fix: items should stay in slot 0
    expect(menu[0].count).to eq 5_u32
    expect(menu[0].item_id_int).to eq 100_u32
  end
end

Spectator.describe "Bug: CraftingMenu missing main<->hotbar fallback" do
  let(:client) { test_client }
  let(:menu) { Rosegold::CraftingMenu.new(client, 1_u8, Rosegold::Chat.new("Crafting")) }

  it "falls back to main<->hotbar when crafting grid is full" do
    # CraftingMenu container_size = 10. Grid slots are 1-9.
    # Fill all grid slots so they can't accept more items.
    (1..9).each { |i| menu[i] = make_slot(200_u32 + i.to_u32, 64_u32) }

    # Put items in main inventory. Container slot 10 = first main inventory slot.
    menu[10] = make_slot(100_u32, 5_u32)

    # Shift-click from main inventory. Grid is full, so vanilla falls back to main->hotbar.
    # Current code: tries grid, fails, returns without moving.
    menu.quick_move_stack(10)

    # After fix: items should move to hotbar (slots 37-45 in window = container_size+27..container_size+36)
    expect(menu[10].empty?).to be_true
  end
end

Spectator.describe "Bug: MerchantMenu shift-click routes player items into merchant input slots" do
  let(:client) { test_client }
  let(:menu) { Rosegold::MerchantMenu.new(client, 1_u8, Rosegold::Chat.new("Merchant")) }

  it "moves player inventory items between main and hotbar, not into merchant inputs" do
    # MerchantMenu container_size = 3. Player inventory starts at index 3.
    # Slot 3 = first main inventory slot in the merchant window.
    # Current code (default ContainerMenu): routes player items into container (merchant input 0-1).
    # Vanilla: player items should move main<->hotbar only.
    menu[3] = make_slot(100_u32, 5_u32)
    menu.quick_move_stack(3)

    # After fix: items should be in hotbar, NOT in merchant input slots
    expect(menu[0].empty?).to be_true
    expect(menu[1].empty?).to be_true
    # Items should have moved to hotbar (container_size+27 = slot 30 in window)
    hotbar_start = 3 + 27 # container_size + 27
    has_items_in_hotbar = (hotbar_start...(hotbar_start + 9)).any? { |i| !menu[i].empty? }
    expect(has_items_in_hotbar).to be_true
  end
end

Spectator.describe "Bug: BrewingStandMenu uses reverse=false for ingredient/fuel container slots" do
  let(:client) { test_client }
  let(:menu) { Rosegold::BrewingStandMenu.new(client, 1_u8, Rosegold::Chat.new("Brewing Stand")) }

  it "shift-clicks ingredient slot (3) to player inventory with reverse=true" do
    # Vanilla BrewingStandMenu.quickMoveStack uses reverse=true for ALL container slots:
    #   moveItemStackTo(var5, 5, 41, true)
    # Current code only uses reverse=true for bottles (0-2), not ingredient (3) or fuel (4).
    # With reverse=true, items should go to the LAST available slot (hotbar end).
    # With reverse=false, items go to the FIRST available slot (main inventory start).

    # container_size=5, so player slots: main=5..31, hotbar=32..40
    menu[3] = make_slot(100_u32, 1_u32) # ingredient slot

    menu.quick_move_stack(3)

    # With reverse=true (vanilla), item lands in last hotbar slot (40)
    expect(menu[40].item_id_int).to eq 100_u32
    # With reverse=false (bug), item would land in first main slot (5)
    expect(menu[5].empty?).to be_true
  end

  it "shift-clicks fuel slot (4) to player inventory with reverse=true" do
    menu[4] = make_slot(200_u32, 1_u32) # fuel slot

    menu.quick_move_stack(4)

    # With reverse=true (vanilla), item lands in last hotbar slot (40)
    expect(menu[40].item_id_int).to eq 200_u32
    expect(menu[5].empty?).to be_true
  end
end

Spectator.describe "Bug: BrewingStandMenu blaze_powder missing main<->hotbar fallback" do
  let(:client) { test_client }
  let(:menu) { Rosegold::BrewingStandMenu.new(client, 1_u8, Rosegold::Chat.new("Brewing Stand")) }

  it "falls back to main<->hotbar when fuel and ingredient slots are full" do
    # Look up blaze_powder ID dynamically (differs between protocol versions)
    bp_id = Rosegold::MCData.default.items.find! { |i| i.name == "blaze_powder" }.id

    # Fill fuel slot (4) and ingredient slot (3) with different items.
    menu[4] = make_slot(bp_id, 64_u32)   # blaze_powder in fuel
    menu[3] = make_slot(200_u32, 64_u32) # something in ingredient

    # Put blaze_powder in main inventory. Container_size = 5, so slot 5 = first main inventory slot.
    menu[5] = make_slot(bp_id, 5_u32)

    # Shift-click from main inventory. Both fuel and ingredient full.
    menu.quick_move_stack(5)

    # After fix: blaze_powder should move to hotbar
    expect(menu[5].empty?).to be_true
    hotbar_start = 5 + 27 # container_size + 27
    has_items_in_hotbar = (hotbar_start...(hotbar_start + 9)).any? { |i| !menu[i].empty? }
    expect(has_items_in_hotbar).to be_true
  end
end

Spectator.describe "Bug: FurnaceMenu missing main<->hotbar fallback" do
  let(:client) { test_client }
  let(:menu) { Rosegold::FurnaceMenu.new(client, 1_u8, Rosegold::Chat.new("Furnace")) }

  it "falls back to main<->hotbar when both ingredient and fuel slots are full" do
    # Fill ingredient (0) and fuel (1) with different items.
    menu[0] = make_slot(200_u32, 64_u32)
    menu[1] = make_slot(201_u32, 64_u32)

    # Put items in main inventory. Container_size = 3, so slot 3 = first main inventory slot.
    menu[3] = make_slot(100_u32, 5_u32)

    # Shift-click from main inventory. Both targets full.
    # Current code: items stay put (no fallback).
    # Vanilla: falls back to main->hotbar.
    menu.quick_move_stack(3)

    # After fix: items should move to hotbar
    expect(menu[3].empty?).to be_true
  end
end
