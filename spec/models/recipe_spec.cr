require "../spec_helper"

# Helper to build a Minecraft::IO::Memory with binary data for parsing
private def build_io(&) : Minecraft::IO::Memory
  writer = Minecraft::IO::Memory.new
  yield writer
  Minecraft::IO::Memory.new(writer.to_slice)
end

# Helper to write a VarInt-encoded SlotDisplay type followed by its data
private def write_slot_display_empty(io)
  io.write 0_u32 # type 0 = Empty
end

private def write_slot_display_any_fuel(io)
  io.write 1_u32 # type 1 = AnyFuel
end

private def write_slot_display_item(io, item_id : UInt32)
  io.write 2_u32 # type 2 = Item
  io.write item_id
end

private def write_slot_display_tag(io, tag : String)
  io.write 4_u32 # type 4 = Tag
  io.write tag
end

# Write a simple empty Slot (count=0)
private def write_empty_slot(io)
  io.write 0_u32 # count=0 means empty
end

# Write a simple non-empty Slot (count, item_id, 0 components add, 0 components remove)
private def write_simple_slot(io, item_id : UInt32, count : UInt32 = 1_u32)
  io.write count
  io.write item_id
  io.write 0_u32 # components_to_add count
  io.write 0_u32 # components_to_remove count
end

private def write_slot_display_item_stack(io, item_id : UInt32, count : UInt32 = 1_u32)
  io.write 3_u32 # type 3 = ItemStack
  write_simple_slot(io, item_id, count)
end

Spectator.describe Rosegold::SlotDisplay do
  # These unit tests use hardcoded 1.21.x wire format type IDs (pre-26.1)
  before_each { Rosegold::Client.protocol_version = 774_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  describe ".read" do
    it "parses Empty (type 0)" do
      io = build_io { |writer| write_slot_display_empty(writer) }
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayEmpty
    end

    it "parses AnyFuel (type 1)" do
      io = build_io { |writer| write_slot_display_any_fuel(writer) }
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayAnyFuel
    end

    it "parses Item (type 2) with item_id" do
      io = build_io { |writer| write_slot_display_item(writer, 42_u32) }
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayItem
      expect(result.as(Rosegold::SlotDisplayItem).item_id).to eq 42_u32
    end

    it "parses ItemStack (type 3) with full Slot" do
      io = build_io { |writer| write_slot_display_item_stack(writer, 10_u32, 5_u32) }
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayItemStack
      slot = result.as(Rosegold::SlotDisplayItemStack).slot
      expect(slot.item_id_int).to eq 10_u32
      expect(slot.count).to eq 5_u32
    end

    it "parses Tag (type 4) with identifier string" do
      io = build_io { |writer| write_slot_display_tag(writer, "minecraft:planks") }
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayTag
      expect(result.as(Rosegold::SlotDisplayTag).tag).to eq "minecraft:planks"
    end

    it "parses SmithingTrimDemo (type 5)" do
      io = build_io do |writer|
        writer.write 5_u32                       # type 5 = SmithingTrimDemo
        write_slot_display_item(writer, 100_u32) # base
        write_slot_display_item(writer, 200_u32) # material
        writer.write 8_u32                       # Holder<TrimPattern>: registry ref 8 means ID 7
      end
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplaySmithingTrimDemo
      demo = result.as(Rosegold::SlotDisplaySmithingTrimDemo)
      expect(demo.base).to be_a Rosegold::SlotDisplayItem
      expect(demo.base.as(Rosegold::SlotDisplayItem).item_id).to eq 100_u32
      expect(demo.material).to be_a Rosegold::SlotDisplayItem
      expect(demo.material.as(Rosegold::SlotDisplayItem).item_id).to eq 200_u32
      expect(demo.pattern).to eq 7_u32
    end

    it "parses WithRemainder (type 6)" do
      io = build_io do |writer|
        writer.write 6_u32                      # type 6 = WithRemainder
        write_slot_display_item(writer, 50_u32) # ingredient
        write_slot_display_item(writer, 60_u32) # remainder
      end
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayWithRemainder
      wr = result.as(Rosegold::SlotDisplayWithRemainder)
      expect(wr.ingredient).to be_a Rosegold::SlotDisplayItem
      expect(wr.ingredient.as(Rosegold::SlotDisplayItem).item_id).to eq 50_u32
      expect(wr.remainder).to be_a Rosegold::SlotDisplayItem
      expect(wr.remainder.as(Rosegold::SlotDisplayItem).item_id).to eq 60_u32
    end

    it "parses Composite (type 7) with multiple options" do
      io = build_io do |writer|
        writer.write 7_u32 # type 7 = Composite
        writer.write 3_u32 # count = 3
        write_slot_display_empty(writer)
        write_slot_display_item(writer, 10_u32)
        write_slot_display_any_fuel(writer)
      end
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayComposite
      composite = result.as(Rosegold::SlotDisplayComposite)
      expect(composite.options.size).to eq 3
      expect(composite.options[0]).to be_a Rosegold::SlotDisplayEmpty
      expect(composite.options[1]).to be_a Rosegold::SlotDisplayItem
      expect(composite.options[2]).to be_a Rosegold::SlotDisplayAnyFuel
    end

    it "parses Composite with zero options" do
      io = build_io do |writer|
        writer.write 7_u32 # type 7 = Composite
        writer.write 0_u32 # count = 0
      end
      result = Rosegold::SlotDisplay.read(io)
      expect(result).to be_a Rosegold::SlotDisplayComposite
      expect(result.as(Rosegold::SlotDisplayComposite).options).to be_empty
    end

    it "raises for unknown type ID" do
      io = build_io(&.write(99_u32))
      expect { Rosegold::SlotDisplay.read(io) }.to raise_error(/Unknown SlotDisplay type: 99/)
    end
  end
end

Spectator.describe Rosegold::RecipeDisplay do
  before_each { Rosegold::Client.protocol_version = 774_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  describe ".read" do
    it "parses ShapedCrafting (type 1)" do
      io = build_io do |writer|
        writer.write 1_u32 # type 1 = ShapedCrafting
        writer.write 2_u32 # width
        writer.write 2_u32 # height
        writer.write 4_u32 # ingredient list count
        # 4 ingredients (2x2)
        write_slot_display_item(writer, 1_u32)
        write_slot_display_item(writer, 2_u32)
        write_slot_display_item(writer, 3_u32)
        write_slot_display_empty(writer)
        # result
        write_slot_display_item(writer, 10_u32)
        # crafting_station
        write_slot_display_item(writer, 20_u32)
      end
      result = Rosegold::RecipeDisplay.read(io)
      expect(result).to be_a Rosegold::RecipeDisplayShapedCrafting
      shaped = result.as(Rosegold::RecipeDisplayShapedCrafting)
      expect(shaped.width).to eq 2_u32
      expect(shaped.height).to eq 2_u32
      expect(shaped.ingredients.size).to eq 4
      expect(shaped.ingredients[0]).to be_a Rosegold::SlotDisplayItem
      expect(shaped.ingredients[3]).to be_a Rosegold::SlotDisplayEmpty
      expect(shaped.result).to be_a Rosegold::SlotDisplayItem
      expect(shaped.result.as(Rosegold::SlotDisplayItem).item_id).to eq 10_u32
      expect(shaped.crafting_station).to be_a Rosegold::SlotDisplayItem
    end

    it "parses ShapedCrafting with 1x1 grid" do
      io = build_io do |writer|
        writer.write 1_u32                      # type 1 = ShapedCrafting
        writer.write 1_u32                      # width
        writer.write 1_u32                      # height
        writer.write 1_u32                      # ingredient list count
        write_slot_display_item(writer, 5_u32)  # 1 ingredient
        write_slot_display_item(writer, 50_u32) # result
        write_slot_display_empty(writer)        # crafting_station
      end
      result = Rosegold::RecipeDisplay.read(io)
      shaped = result.as(Rosegold::RecipeDisplayShapedCrafting)
      expect(shaped.width).to eq 1_u32
      expect(shaped.height).to eq 1_u32
      expect(shaped.ingredients.size).to eq 1
    end

    it "parses ShapelessCrafting (type 0)" do
      io = build_io do |writer|
        writer.write 0_u32 # type 0 = ShapelessCrafting
        writer.write 2_u32 # ingredient count
        write_slot_display_item(writer, 1_u32)
        write_slot_display_item(writer, 2_u32)
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_item(writer, 20_u32) # crafting_station
      end
      result = Rosegold::RecipeDisplay.read(io)
      expect(result).to be_a Rosegold::RecipeDisplayShapelessCrafting
      shapeless = result.as(Rosegold::RecipeDisplayShapelessCrafting)
      expect(shapeless.ingredients.size).to eq 2
      expect(shapeless.result).to be_a Rosegold::SlotDisplayItem
      expect(shapeless.crafting_station).to be_a Rosegold::SlotDisplayItem
    end

    it "parses ShapelessCrafting with zero ingredients" do
      io = build_io do |writer|
        writer.write 0_u32                      # type 0 = ShapelessCrafting
        writer.write 0_u32                      # zero ingredients
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_empty(writer)        # crafting_station
      end
      result = Rosegold::RecipeDisplay.read(io)
      shapeless = result.as(Rosegold::RecipeDisplayShapelessCrafting)
      expect(shapeless.ingredients).to be_empty
    end

    it "parses Furnace (type 2) with cooking_time and experience" do
      io = build_io do |writer|
        writer.write 2_u32                      # type 2 = Furnace
        write_slot_display_item(writer, 1_u32)  # ingredient
        write_slot_display_any_fuel(writer)     # fuel
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_item(writer, 20_u32) # crafting_station
        writer.write 200_u32                    # cooking_time
        writer.write_full 0.35_f32              # experience
      end
      result = Rosegold::RecipeDisplay.read(io)
      expect(result).to be_a Rosegold::RecipeDisplayFurnace
      furnace = result.as(Rosegold::RecipeDisplayFurnace)
      expect(furnace.ingredient).to be_a Rosegold::SlotDisplayItem
      expect(furnace.fuel).to be_a Rosegold::SlotDisplayAnyFuel
      expect(furnace.result).to be_a Rosegold::SlotDisplayItem
      expect(furnace.cooking_time).to eq 200_u32
      expect(furnace.experience).to be_close(0.35_f32, 0.001)
    end

    it "parses Stonecutter (type 3)" do
      io = build_io do |writer|
        writer.write 3_u32                      # type 3 = Stonecutter
        write_slot_display_item(writer, 1_u32)  # ingredient
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_item(writer, 20_u32) # crafting_station
      end
      result = Rosegold::RecipeDisplay.read(io)
      expect(result).to be_a Rosegold::RecipeDisplayStonecutter
      sc = result.as(Rosegold::RecipeDisplayStonecutter)
      expect(sc.ingredient).to be_a Rosegold::SlotDisplayItem
      expect(sc.result).to be_a Rosegold::SlotDisplayItem
      expect(sc.crafting_station).to be_a Rosegold::SlotDisplayItem
    end

    it "parses Smithing (type 4)" do
      io = build_io do |writer|
        writer.write 4_u32                      # type 4 = Smithing
        write_slot_display_item(writer, 1_u32)  # template
        write_slot_display_item(writer, 2_u32)  # base
        write_slot_display_item(writer, 3_u32)  # addition
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_item(writer, 20_u32) # crafting_station
      end
      result = Rosegold::RecipeDisplay.read(io)
      expect(result).to be_a Rosegold::RecipeDisplaySmithing
      smithing = result.as(Rosegold::RecipeDisplaySmithing)
      expect(smithing.template.as(Rosegold::SlotDisplayItem).item_id).to eq 1_u32
      expect(smithing.base.as(Rosegold::SlotDisplayItem).item_id).to eq 2_u32
      expect(smithing.addition.as(Rosegold::SlotDisplayItem).item_id).to eq 3_u32
      expect(smithing.result.as(Rosegold::SlotDisplayItem).item_id).to eq 10_u32
      expect(smithing.crafting_station.as(Rosegold::SlotDisplayItem).item_id).to eq 20_u32
    end

    it "raises for unknown type ID" do
      io = build_io(&.write(99_u32))
      expect { Rosegold::RecipeDisplay.read(io) }.to raise_error(/Unknown RecipeDisplay type: 99/)
    end
  end
end

Spectator.describe Rosegold::RecipeDisplayEntry do
  before_each { Rosegold::Client.protocol_version = 774_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  describe ".read" do
    it "parses entry with no group and no crafting requirements" do
      io = build_io do |writer|
        writer.write 42_u32 # id
        # ShapelessCrafting display
        writer.write 0_u32                      # RecipeDisplay type 0
        writer.write 1_u32                      # ingredient count
        write_slot_display_item(writer, 5_u32)  # ingredient
        write_slot_display_item(writer, 10_u32) # result
        write_slot_display_empty(writer)        # crafting_station
        # group (0 = none)
        writer.write 0_u32
        # category
        writer.write 3_u32
        # has_requirements = false
        writer.write false
      end
      entry = Rosegold::RecipeDisplayEntry.read(io)
      expect(entry.id).to eq 42_u32
      expect(entry.display).to be_a Rosegold::RecipeDisplayShapelessCrafting
      expect(entry.group).to be_nil
      expect(entry.category).to eq 3_u32
      expect(entry.crafting_requirements).to be_nil
    end

    it "parses entry with group present" do
      io = build_io do |writer|
        writer.write 1_u32 # id
        # ShapelessCrafting display
        writer.write 0_u32 # RecipeDisplay type 0
        writer.write 0_u32 # zero ingredients
        write_slot_display_item(writer, 10_u32)
        write_slot_display_empty(writer)
        # group = 5 (encoded as 6, since 0 means none, value = group_id - 1)
        writer.write 6_u32
        # category
        writer.write 0_u32
        # has_requirements = false
        writer.write false
      end
      entry = Rosegold::RecipeDisplayEntry.read(io)
      expect(entry.group).to eq 5_u32
    end

    it "parses entry with crafting requirements" do
      io = build_io do |writer|
        writer.write 1_u32 # id
        # ShapelessCrafting display
        writer.write 0_u32 # RecipeDisplay type 0
        writer.write 0_u32 # zero ingredients
        write_slot_display_item(writer, 10_u32)
        write_slot_display_empty(writer)
        # group = none
        writer.write 0_u32
        # category
        writer.write 0_u32
        # has_requirements = true
        writer.write true
        # 2 requirement groups (HolderSet format)
        writer.write 2_u32
        # first group: direct list, type=3 (2+1), 2 item IDs
        writer.write 3_u32
        writer.write 100_u32
        writer.write 200_u32
        # second group: direct list, type=2 (1+1), 1 item ID
        writer.write 2_u32
        writer.write 300_u32
      end
      entry = Rosegold::RecipeDisplayEntry.read(io)
      reqs = entry.crafting_requirements
      expect(reqs).not_to be_nil
      if reqs
        expect(reqs.size).to eq 2
        expect(reqs[0]).to eq [100_u32, 200_u32]
        expect(reqs[1]).to eq [300_u32]
      end
    end

    it "returns result_item_id for ShapelessCrafting with Item result" do
      display = Rosegold::RecipeDisplayShapelessCrafting.new(
        [] of Rosegold::SlotDisplay,
        Rosegold::SlotDisplayItem.new(42_u32),
        Rosegold::SlotDisplayEmpty.new
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to eq 42_u32
    end

    it "returns result_item_id for ShapedCrafting with Item result" do
      display = Rosegold::RecipeDisplayShapedCrafting.new(
        1_u32, 1_u32,
        [Rosegold::SlotDisplayEmpty.new] of Rosegold::SlotDisplay,
        Rosegold::SlotDisplayItem.new(99_u32),
        Rosegold::SlotDisplayEmpty.new
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to eq 99_u32
    end

    it "returns nil result_item_id when result is not SlotDisplayItem" do
      display = Rosegold::RecipeDisplayShapelessCrafting.new(
        [] of Rosegold::SlotDisplay,
        Rosegold::SlotDisplayEmpty.new,
        Rosegold::SlotDisplayEmpty.new
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to be_nil
    end

    it "returns result_item_id for Furnace" do
      display = Rosegold::RecipeDisplayFurnace.new(
        Rosegold::SlotDisplayItem.new(1_u32),
        Rosegold::SlotDisplayAnyFuel.new,
        Rosegold::SlotDisplayItem.new(50_u32),
        Rosegold::SlotDisplayEmpty.new,
        200_u32, 0.5_f32
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to eq 50_u32
    end

    it "returns result_item_id for Stonecutter" do
      display = Rosegold::RecipeDisplayStonecutter.new(
        Rosegold::SlotDisplayItem.new(1_u32),
        Rosegold::SlotDisplayItem.new(70_u32),
        Rosegold::SlotDisplayEmpty.new
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to eq 70_u32
    end

    it "returns result_item_id for Smithing" do
      display = Rosegold::RecipeDisplaySmithing.new(
        Rosegold::SlotDisplayItem.new(1_u32),
        Rosegold::SlotDisplayItem.new(2_u32),
        Rosegold::SlotDisplayItem.new(3_u32),
        Rosegold::SlotDisplayItem.new(80_u32),
        Rosegold::SlotDisplayEmpty.new
      )
      entry = Rosegold::RecipeDisplayEntry.new(1_u32, display, nil, 0_u32, nil)
      expect(entry.result_item_id).to eq 80_u32
    end
  end
end

Spectator.describe Rosegold::RecipeRegistry do
  let(:registry) { Rosegold::RecipeRegistry.new }

  def make_entry(id : UInt32, result_item_id : UInt32 = 0_u32) : Rosegold::RecipeDisplayEntry
    display = Rosegold::RecipeDisplayShapelessCrafting.new(
      [] of Rosegold::SlotDisplay,
      Rosegold::SlotDisplayItem.new(result_item_id),
      Rosegold::SlotDisplayEmpty.new
    )
    Rosegold::RecipeDisplayEntry.new(id, display, nil, 0_u32, nil)
  end

  describe "#add" do
    it "adds entries" do
      registry.add([make_entry(1_u32), make_entry(2_u32)], replace: false)
      expect(registry.size).to eq 2
    end

    it "overwrites entries with same ID" do
      registry.add([make_entry(1_u32, 10_u32)], replace: false)
      registry.add([make_entry(1_u32, 20_u32)], replace: false)
      expect(registry.size).to eq 1
      found = registry.find_by_id(1_u32)
      expect(found).not_to be_nil
      expect(found.try &.result_item_id).to eq 20_u32
    end

    it "appends when replace is false" do
      registry.add([make_entry(1_u32)], replace: false)
      registry.add([make_entry(2_u32)], replace: false)
      expect(registry.size).to eq 2
    end

    it "clears before adding when replace is true" do
      registry.add([make_entry(1_u32)], replace: false)
      registry.add([make_entry(2_u32)], replace: true)
      expect(registry.size).to eq 1
      expect(registry.find_by_id(1_u32)).to be_nil
      expect(registry.find_by_id(2_u32)).not_to be_nil
    end
  end

  describe "#find_by_id" do
    it "returns entry when found" do
      registry.add([make_entry(5_u32)], replace: false)
      entry = registry.find_by_id(5_u32)
      expect(entry).not_to be_nil
      expect(entry.try &.id).to eq 5_u32
    end

    it "returns nil when not found" do
      expect(registry.find_by_id(999_u32)).to be_nil
    end
  end

  describe "#remove" do
    it "removes entries by ID" do
      registry.add([make_entry(1_u32), make_entry(2_u32), make_entry(3_u32)], replace: false)
      registry.remove([1_u32, 3_u32])
      expect(registry.size).to eq 1
      expect(registry.find_by_id(1_u32)).to be_nil
      expect(registry.find_by_id(2_u32)).not_to be_nil
      expect(registry.find_by_id(3_u32)).to be_nil
    end

    it "ignores non-existent IDs" do
      registry.add([make_entry(1_u32)], replace: false)
      registry.remove([999_u32])
      expect(registry.size).to eq 1
    end
  end

  describe "#clear" do
    it "removes all entries" do
      registry.add([make_entry(1_u32), make_entry(2_u32)], replace: false)
      registry.clear
      expect(registry.size).to eq 0
    end
  end

  describe "#size" do
    it "returns 0 for empty registry" do
      expect(registry.size).to eq 0
    end

    it "returns correct count" do
      registry.add([make_entry(1_u32), make_entry(2_u32), make_entry(3_u32)], replace: false)
      expect(registry.size).to eq 3
    end
  end
end
