module Rosegold
  abstract class SlotDisplay
    def self.read(io) : SlotDisplay
      type_id = io.read_var_int
      if Client.protocol_version >= 775_u32
        # 26.1: 3 new types inserted — with_any_potion(2), only_with_component(3), dyed(7)
        case type_id
        when  0 then SlotDisplayEmpty.new
        when  1 then SlotDisplayAnyFuel.new
        when  2 then SlotDisplayWithAnyPotion.read(io)
        when  3 then SlotDisplayOnlyWithComponent.read(io)
        when  4 then SlotDisplayItem.read(io)
        when  5 then SlotDisplayItemStack.read(io)
        when  6 then SlotDisplayTag.read(io)
        when  7 then SlotDisplayDyed.read(io)
        when  8 then SlotDisplaySmithingTrimDemo.read(io)
        when  9 then SlotDisplayWithRemainder.read(io)
        when 10 then SlotDisplayComposite.read(io)
        else         raise "Unknown SlotDisplay type: #{type_id} (protocol 775)"
        end
      else
        case type_id
        when 0 then SlotDisplayEmpty.new
        when 1 then SlotDisplayAnyFuel.new
        when 2 then SlotDisplayItem.read(io)
        when 3 then SlotDisplayItemStack.read(io)
        when 4 then SlotDisplayTag.read(io)
        when 5 then SlotDisplaySmithingTrimDemo.read(io)
        when 6 then SlotDisplayWithRemainder.read(io)
        when 7 then SlotDisplayComposite.read(io)
        else        raise "Unknown SlotDisplay type: #{type_id}"
        end
      end
    end

    def item_id : UInt32?
      case display = self
      when SlotDisplayItem              then display.item_id
      when SlotDisplayItemStack         then display.slot.item_id_int.to_u32
      when SlotDisplayComposite         then display.options.first?.try &.item_id
      when SlotDisplayWithRemainder     then display.ingredient.item_id
      when SlotDisplayWithAnyPotion     then display.display.item_id
      when SlotDisplayOnlyWithComponent then display.source.item_id
      when SlotDisplayDyed              then display.target.item_id
      end
    end

    def all_item_ids : Array(UInt32)
      case display = self
      when SlotDisplayItem              then [display.item_id]
      when SlotDisplayItemStack         then [display.slot.item_id_int.to_u32]
      when SlotDisplayComposite         then display.options.compact_map(&.item_id)
      when SlotDisplayWithRemainder     then display.ingredient.all_item_ids
      when SlotDisplayWithAnyPotion     then display.display.all_item_ids
      when SlotDisplayOnlyWithComponent then display.source.all_item_ids
      when SlotDisplayDyed              then display.target.all_item_ids
      else                                   id = item_id; id ? [id] : [] of UInt32
      end
    end
  end

  class SlotDisplayEmpty < SlotDisplay; end

  class SlotDisplayAnyFuel < SlotDisplay; end

  class SlotDisplayItem < SlotDisplay
    getter item_id : UInt32

    def initialize(@item_id); end

    def self.read(io) : self
      new(io.read_var_int)
    end
  end

  class SlotDisplayItemStack < SlotDisplay
    getter slot : Slot

    def initialize(@slot); end

    def self.read(io) : self
      if Client.protocol_version >= 775_u32
        # 26.1: ItemStackTemplate = item_holder, count, component_patch
        # Different field order from Slot: item first, then count (Slot has count first)
        item_id = io.read_var_int
        count = io.read_var_int
        # Component patch uses same format as Slot: add_count + remove_count + components
        components_to_add_count = io.read_var_int
        components_to_remove_count = io.read_var_int
        components_to_add = Hash(String, DataComponent).new
        components_to_add_count.times do
          component_type = io.read_var_int
          name = DataComponentTypes.name_for(component_type, Client.protocol_version) || "unknown_#{component_type}"
          structured_component = DataComponent.create_component(component_type, io)
          components_to_add[name] = structured_component
        end
        components_to_remove = Set(String).new
        components_to_remove_count.times do
          component_type = io.read_var_int
          name = DataComponentTypes.name_for(component_type, Client.protocol_version) || "unknown_#{component_type}"
          components_to_remove.add(name)
        end
        new(Slot.new(count: count, item_id_int: item_id, components_to_add: components_to_add, components_to_remove: components_to_remove))
      else
        new(Slot.read(io))
      end
    end
  end

  class SlotDisplayTag < SlotDisplay
    getter tag : String

    def initialize(@tag); end

    def self.read(io) : self
      new(io.read_var_string)
    end
  end

  class SlotDisplaySmithingTrimDemo < SlotDisplay
    getter base : SlotDisplay
    getter material : SlotDisplay
    getter pattern : UInt32

    def initialize(@base, @material, @pattern); end

    def self.read(io) : self
      base = SlotDisplay.read(io)
      material = SlotDisplay.read(io)
      # Holder<TrimPattern>: 0 = direct (inline data), >0 = registry reference (value - 1)
      holder_type = io.read_var_int
      if holder_type == 0_u32
        # Direct holder: TrimPattern has ResourceLocation, Holder<Item>, Component, Bool.
        # Too complex to skip reliably; servers virtually always send registry references.
        raise "Direct Holder<TrimPattern> not supported in SlotDisplaySmithingTrimDemo"
      end
      pattern = holder_type - 1
      new(base, material, pattern)
    end
  end

  class SlotDisplayWithRemainder < SlotDisplay
    getter ingredient : SlotDisplay
    getter remainder : SlotDisplay

    def initialize(@ingredient, @remainder); end

    def self.read(io) : self
      ingredient = SlotDisplay.read(io)
      remainder = SlotDisplay.read(io)
      new(ingredient, remainder)
    end
  end

  class SlotDisplayComposite < SlotDisplay
    getter options : Array(SlotDisplay)

    def initialize(@options); end

    def self.read(io) : self
      count = io.read_var_int
      options = Array(SlotDisplay).new(count.to_i)
      count.times { options << SlotDisplay.read(io) }
      new(options)
    end
  end

  # 26.1+ new SlotDisplay types
  class SlotDisplayWithAnyPotion < SlotDisplay
    getter display : SlotDisplay

    def initialize(@display); end

    def self.read(io) : self
      new(SlotDisplay.read(io))
    end
  end

  class SlotDisplayOnlyWithComponent < SlotDisplay
    getter source : SlotDisplay
    getter component_type_id : UInt32

    def initialize(@source, @component_type_id); end

    def self.read(io) : self
      source = SlotDisplay.read(io)
      component_type_id = io.read_var_int
      new(source, component_type_id)
    end
  end

  class SlotDisplayDyed < SlotDisplay
    getter dye : SlotDisplay
    getter target : SlotDisplay

    def initialize(@dye, @target); end

    def self.read(io) : self
      dye = SlotDisplay.read(io)
      target = SlotDisplay.read(io)
      new(dye, target)
    end
  end

  abstract class RecipeDisplay
    def self.read(io) : RecipeDisplay
      type_id = io.read_var_int
      case type_id
      when 0 then RecipeDisplayShapelessCrafting.read(io)
      when 1 then RecipeDisplayShapedCrafting.read(io)
      when 2 then RecipeDisplayFurnace.read(io)
      when 3 then RecipeDisplayStonecutter.read(io)
      when 4 then RecipeDisplaySmithing.read(io)
      else        raise "Unknown RecipeDisplay type: #{type_id}"
      end
    end
  end

  class RecipeDisplayShapedCrafting < RecipeDisplay
    getter width : UInt32
    getter height : UInt32
    getter ingredients : Array(SlotDisplay)
    getter result : SlotDisplay
    getter crafting_station : SlotDisplay

    def initialize(@width, @height, @ingredients, @result, @crafting_station); end

    def self.read(io) : self
      width = io.read_var_int
      height = io.read_var_int
      count = io.read_var_int
      ingredients = Array(SlotDisplay).new(count.to_i)
      count.times { ingredients << SlotDisplay.read(io) }
      result = SlotDisplay.read(io)
      crafting_station = SlotDisplay.read(io)
      new(width, height, ingredients, result, crafting_station)
    end
  end

  class RecipeDisplayShapelessCrafting < RecipeDisplay
    getter ingredients : Array(SlotDisplay)
    getter result : SlotDisplay
    getter crafting_station : SlotDisplay

    def initialize(@ingredients, @result, @crafting_station); end

    def self.read(io) : self
      count = io.read_var_int
      ingredients = Array(SlotDisplay).new(count.to_i)
      count.times { ingredients << SlotDisplay.read(io) }
      result = SlotDisplay.read(io)
      crafting_station = SlotDisplay.read(io)
      new(ingredients, result, crafting_station)
    end
  end

  class RecipeDisplayFurnace < RecipeDisplay
    getter ingredient : SlotDisplay
    getter fuel : SlotDisplay
    getter result : SlotDisplay
    getter crafting_station : SlotDisplay
    getter cooking_time : UInt32
    getter experience : Float32

    def initialize(@ingredient, @fuel, @result, @crafting_station, @cooking_time, @experience); end

    def self.read(io) : self
      ingredient = SlotDisplay.read(io)
      fuel = SlotDisplay.read(io)
      result = SlotDisplay.read(io)
      crafting_station = SlotDisplay.read(io)
      cooking_time = io.read_var_int
      experience = io.read_float
      new(ingredient, fuel, result, crafting_station, cooking_time, experience)
    end
  end

  class RecipeDisplayStonecutter < RecipeDisplay
    getter ingredient : SlotDisplay
    getter result : SlotDisplay
    getter crafting_station : SlotDisplay

    def initialize(@ingredient, @result, @crafting_station); end

    def self.read(io) : self
      ingredient = SlotDisplay.read(io)
      result = SlotDisplay.read(io)
      crafting_station = SlotDisplay.read(io)
      new(ingredient, result, crafting_station)
    end
  end

  class RecipeDisplaySmithing < RecipeDisplay
    getter template : SlotDisplay
    getter base : SlotDisplay
    getter addition : SlotDisplay
    getter result : SlotDisplay
    getter crafting_station : SlotDisplay

    def initialize(@template, @base, @addition, @result, @crafting_station); end

    def self.read(io) : self
      template = SlotDisplay.read(io)
      base = SlotDisplay.read(io)
      addition = SlotDisplay.read(io)
      result = SlotDisplay.read(io)
      crafting_station = SlotDisplay.read(io)
      new(template, base, addition, result, crafting_station)
    end
  end

  class RecipeDisplayEntry
    getter id : UInt32
    getter display : RecipeDisplay
    getter group : UInt32?
    getter category : UInt32
    getter crafting_requirements : Array(Array(UInt32))?

    def initialize(@id, @display, @group, @category, @crafting_requirements); end

    def self.read(io) : self
      id = io.read_var_int
      display = RecipeDisplay.read(io)

      group_id = io.read_var_int
      group = group_id == 0_u32 ? nil : group_id - 1

      category = io.read_var_int

      has_requirements = io.read_bool
      crafting_requirements = if has_requirements
                                req_count = io.read_var_int
                                raise ArgumentError.new("Invalid crafting requirement count: #{req_count} (max 1000)") if req_count > 1000_u32
                                Array(Array(UInt32)).new(req_count.to_i).tap do |reqs|
                                  req_count.times do
                                    reqs << read_ingredient(io)
                                  end
                                end
                              end

      new(id, display, group, category, crafting_requirements)
    end

    # Reads a HolderSet<Item> (Ingredient) from the wire.
    # type=0: tag-based (string identifier, resolved to empty array)
    # type>0: direct list of (type-1) item IDs
    private def self.read_ingredient(io) : Array(UInt32)
      type = io.read_var_int
      if type == 0_u32
        io.read_var_string # tag identifier, skip
        [] of UInt32
      else
        count = type - 1
        Array(UInt32).new(count.to_i).tap do |items|
          count.times { items << io.read_var_int }
        end
      end
    end

    def result_item_id : UInt32?
      result_display = case display
                       when RecipeDisplayShapedCrafting    then display.result
                       when RecipeDisplayShapelessCrafting then display.result
                       when RecipeDisplayFurnace           then display.result
                       when RecipeDisplayStonecutter       then display.result
                       when RecipeDisplaySmithing          then display.result
                       end
      result_display.try &.item_id
    end
  end

  class RecipeRegistry
    getter entries : Hash(UInt32, RecipeDisplayEntry)
    getter last_parse_error : String?
    getter last_expected_count : UInt32?
    getter add_history : Array(String)

    def initialize
      @entries = Hash(UInt32, RecipeDisplayEntry).new
      @add_history = [] of String
    end

    def record_parse_error(error : String, expected_count : UInt32)
      @last_parse_error = error
      @last_expected_count = expected_count
    end

    def add(new_entries : Array(RecipeDisplayEntry), replace : Bool)
      @add_history << "add(#{new_entries.size}, replace=#{replace}) before=#{@entries.size}"
      clear if replace
      new_entries.each { |entry| @entries[entry.id] = entry }
    end

    def remove(ids : Array(UInt32))
      ids.each { |id| @entries.delete(id) }
    end

    def find_by_id(id : UInt32) : RecipeDisplayEntry?
      @entries[id]?
    end

    def find_by_result(item_name : String) : Array(RecipeDisplayEntry)
      mcdata = MCData.default
      target_item = mcdata.items.find { |i| i.name == item_name }
      return [] of RecipeDisplayEntry unless target_item

      target_id = target_item.id
      @entries.values.select { |entry| entry.result_item_id == target_id }
    end

    def clear
      @entries.clear
    end

    def size
      @entries.size
    end
  end
end
