require "../../minecraft/nbt"
require "digest/crc32"

# Data Component types for 1.21.8
enum Rosegold::DataComponentType : UInt32
  CustomData               =  0
  MaxStackSize             =  1
  MaxDamage                =  2
  Damage                   =  3
  Unbreakable              =  4
  CustomName               =  5
  ItemName                 =  6
  ItemModel                =  7
  Lore                     =  8
  Rarity                   =  9
  Enchantments             = 10
  CanPlaceOn               = 11
  CanBreak                 = 12
  AttributeModifiers       = 13
  CustomModelData          = 14
  TooltipDisplay           = 15
  RepairCost               = 16
  CreativeSlotLock         = 17
  EnchantmentGlintOverride = 18
  IntangibleProjectile     = 19
  Food                     = 20
  Consumable               = 21
  UseRemainder             = 22
  UseCooldown              = 23
  DamageResistant          = 24
  Tool                     = 25
  Weapon                   = 26
  Enchantable              = 27
  Equippable               = 28
  Repairable               = 29
  Glider                   = 30
  TooltipStyle             = 31
  DeathProtection          = 32
  BlocksAttacks            = 33
  StoredEnchantments       = 34
  DyedColor                = 35
  MapColor                 = 36
  MapId                    = 37
  MapDecorations           = 38
  MapPostProcessing        = 39
  ChargedProjectiles       = 40
  BundleContents           = 41
  PotionContents           = 42
  PotionDurationScale      = 43
  SuspiciousStewEffects    = 44
  WritableBookContent      = 45
  WrittenBookContent       = 46
  Trim                     = 47
  DebugStickState          = 48
  EntityData               = 49
  BucketEntityData         = 50
  BlockEntityData          = 51
  Instrument               = 52
  ProvidesTrimMaterial     = 53
  OminousBottleAmplifier   = 54
  JukeboxPlayable          = 55
  ProvidesBannerPatterns   = 56
  Recipes                  = 57
  LodestoneTracker         = 58
  FireworkExplosion        = 59
  Fireworks                = 60
  Profile                  = 61
  NoteBlockSound           = 62
  BannerPatterns           = 63
  BaseColor                = 64
  PotDecorations           = 65
  Container                = 66
  BlockState               = 67
  Bees                     = 68
  Lock                     = 69
  ContainerLoot            = 70
  BreakSound               = 71
  VillagerVariant          = 72
  WolfVariant              = 73
  WolfSoundVariant         = 74
  WolfCollar               = 75
  FoxVariant               = 76
  SalmonSize               = 77
  ParrotVariant            = 78
  TropicalFishPattern      = 79
  TropicalFishBaseColor    = 80
  TropicalFishPatternColor = 81
  MooshroomVariant         = 82
  RabbitVariant            = 83
  PigVariant               = 84
  CowVariant               = 85
  ChickenVariant           = 86
  FrogVariant              = 87
  HorseVariant             = 88
  PaintingVariant          = 89
  LlamaVariant             = 90
  AxolotlVariant           = 91
  CatVariant               = 92
  CatCollar                = 93
  SheepColor               = 94
  ShulkerColor             = 95
end

# Base class for data components
abstract class Rosegold::DataComponent
  abstract def write(io) : Nil

  # Factory method to create structured components by type ID
  def self.create_component(component_type : UInt32, io) : DataComponent
    case component_type
    when 0 # minecraft:custom_data - NBT compound
      DataComponents::CustomData.read(io)
    when 1 # minecraft:max_stack_size - VarInt
      DataComponents::MaxStackSize.read(io)
    when 2 # minecraft:max_damage - VarInt
      DataComponents::MaxDamage.read(io)
    when 3 # minecraft:damage - VarInt
      DataComponents::Damage.read(io)
    when 4 # minecraft:unbreakable - no fields
      DataComponents::Unbreakable.read(io)
    when 5 # minecraft:custom_name - Text Component (NBT)
      DataComponents::CustomName.read(io)
    when 6 # minecraft:item_name - Text Component (NBT)
      DataComponents::ItemName.read(io)
    when 7 # minecraft:item_model - Identifier (String)
      DataComponents::ItemModel.read(io)
    when 9 # minecraft:rarity - VarInt enum
      DataComponents::Rarity.read(io)
    when 10 # minecraft:enchantments - Complex structure
      DataComponents::Enchantments.read(io)
    when 16 # minecraft:repair_cost - VarInt
      DataComponents::RepairCost.read(io)
    when 17 # minecraft:creative_slot_lock - no fields
      DataComponents::CreativeSlotLock.read(io)
    when 18 # minecraft:enchantment_glint_override - Boolean
      DataComponents::EnchantmentGlintOverride.read(io)
    else
      # For unknown components, skip/ignore to avoid decoding failures
      DataComponents::Unknown.read(io)
    end
  end
end

# Component for damage (simple VarInt)
class Rosegold::DataComponents::Damage < Rosegold::DataComponent
  property value : UInt32

  def initialize(@value : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write_var_int value
  end
end

# Component for max damage (simple VarInt)
class Rosegold::DataComponents::MaxDamage < Rosegold::DataComponent
  property value : UInt32

  def initialize(@value : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write_var_int value
  end
end

# Component for max stack size (simple VarInt)
class Rosegold::DataComponents::MaxStackSize < Rosegold::DataComponent
  property value : UInt32

  def initialize(@value : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write_var_int value
  end
end

# Component for repair cost (simple VarInt)
class Rosegold::DataComponents::RepairCost < Rosegold::DataComponent
  property cost : UInt32

  def initialize(@cost : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write_var_int cost
  end
end

# Component for enchantments (complex structure)
class Rosegold::DataComponents::Enchantments < Rosegold::DataComponent
  property enchantments : Hash(UInt32, UInt32) # type_id -> level

  def initialize(@enchantments : Hash(UInt32, UInt32) = Hash(UInt32, UInt32).new); end

  def self.read(io) : self
    enchant_count = io.read_var_int
    enchantments = Hash(UInt32, UInt32).new
    enchant_count.times do
      type_id = io.read_var_int
      level = io.read_var_int
      enchantments[type_id] = level
    end
    new(enchantments)
  end

  def write(io) : Nil
    io.write_var_int enchantments.size
    enchantments.each do |type_id, level|
      io.write_var_int type_id
      io.write_var_int level
    end
  end
end

# Component for custom name (Text Component)
class Rosegold::DataComponents::CustomName < Rosegold::DataComponent
  property value : String

  def initialize(@value : String); end

  def self.read(io) : self
    # Read as NBT Text Component
    nbt = io.read_nbt
    name = case nbt
           when Minecraft::NBT::StringTag
             nbt.value
           when Minecraft::NBT::CompoundTag
             nbt["text"]?.try(&.as(Minecraft::NBT::StringTag).value) || "Unknown"
           else
             "Unknown"
           end
    new(name)
  end

  def write(io) : Nil
    # Write as simple string NBT for now
    io.write Minecraft::NBT::StringTag.new(value)
  end
end

# Component for custom data (NBT compound)
class Rosegold::DataComponents::CustomData < Rosegold::DataComponent
  property data : Minecraft::NBT::Tag

  def initialize(@data : Minecraft::NBT::Tag); end

  def self.read(io) : self
    new(io.read_nbt)
  end

  def write(io) : Nil
    io.write data
  end
end

# Component for unbreakable (no fields)
class Rosegold::DataComponents::Unbreakable < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    new
  end

  def write(io) : Nil
    # No fields to write
  end
end

# Component for item_name (Text Component)
class Rosegold::DataComponents::ItemName < Rosegold::DataComponent
  property value : String

  def initialize(@value : String); end

  def self.read(io) : self
    # Read as NBT Text Component
    nbt = io.read_nbt
    name = case nbt
           when Minecraft::NBT::StringTag
             nbt.value
           when Minecraft::NBT::CompoundTag
             nbt["text"]?.try(&.as(Minecraft::NBT::StringTag).value) || "Unknown"
           else
             "Unknown"
           end
    new(name)
  end

  def write(io) : Nil
    io.write Minecraft::NBT::StringTag.new(value)
  end
end

# Component for item_model (Identifier - String)
class Rosegold::DataComponents::ItemModel < Rosegold::DataComponent
  property model : String

  def initialize(@model : String); end

  def self.read(io) : self
    new(io.read_var_string)
  end

  def write(io) : Nil
    io.write_var_string model
  end
end

# Component for rarity (VarInt enum)
class Rosegold::DataComponents::Rarity < Rosegold::DataComponent
  property rarity : UInt32

  def initialize(@rarity : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write_var_int rarity
  end
end

# Component for creative_slot_lock (no fields)
class Rosegold::DataComponents::CreativeSlotLock < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    new
  end

  def write(io) : Nil
    # No fields to write
  end
end

# Component for enchantment_glint_override (Boolean)
class Rosegold::DataComponents::EnchantmentGlintOverride < Rosegold::DataComponent
  property has_glint : Bool

  def initialize(@has_glint : Bool); end

  def self.read(io) : self
    new(io.read_bool)
  end

  def write(io) : Nil
    io.write has_glint
  end
end

# Generic component for unknown types (stores raw bytes)
class Rosegold::DataComponents::Unknown < Rosegold::DataComponent
  property data : Bytes

  def initialize(@data : Bytes); end

  def self.read(io) : self
    # For unknown components, we can't know how much to read
    # This is a fallback that should ideally not be used
    new(Bytes.new(0))
  end

  def write(io) : Nil
    io.write data
  end
end

class Rosegold::Slot
  property count : UInt32
  property item_id_int : UInt32
  property components_to_add : Hash(UInt32, DataComponent) # Component type -> structured component
  property components_to_remove : Set(UInt32)              # Component types to remove

  @cached_item : MCData::Item?

  # Enchantment type mapping for better maintainability
  ENCHANTMENT_TYPE_MAP = {
     0_u32 => "protection",
     1_u32 => "fire_protection",
     2_u32 => "feather_falling",
     3_u32 => "blast_protection",
     4_u32 => "projectile_protection",
     5_u32 => "respiration",
     6_u32 => "aqua_affinity",
     7_u32 => "thorns",
     8_u32 => "depth_strider",
     9_u32 => "frost_walker",
    10_u32 => "binding_curse",
    11_u32 => "soul_speed",
    12_u32 => "swift_sneak",
    13_u32 => "sharpness",
    14_u32 => "smite",
    15_u32 => "bane_of_arthropods",
    16_u32 => "knockback",
    17_u32 => "fire_aspect",
    18_u32 => "looting",
    19_u32 => "sweeping",
    20_u32 => "efficiency",
    21_u32 => "silk_touch",
    22_u32 => "unbreaking",
    23_u32 => "fortune",
    24_u32 => "power",
    25_u32 => "punch",
    26_u32 => "flame",
    27_u32 => "infinity",
    28_u32 => "luck_of_the_sea",
    29_u32 => "lure",
    30_u32 => "loyalty",
    31_u32 => "impaling",
    32_u32 => "riptide",
    33_u32 => "channeling",
    34_u32 => "multishot",
    35_u32 => "quick_charge",
    36_u32 => "piercing",
    37_u32 => "density",
    38_u32 => "breach",
    39_u32 => "wind_burst",
    40_u32 => "mending",
    41_u32 => "vanishing_curse",
  }

  def initialize(@count = 0_u32, @item_id_int = 0_u32, @components_to_add = Hash(UInt32, DataComponent).new, @components_to_remove = Set(UInt32).new); end

  def self.read(io) : Rosegold::Slot
    count = io.read_var_int
    return new(count) if count == 0 # Empty slot

    item_id_int = io.read_var_int

    # Read components to add
    components_to_add_count = io.read_var_int
    components_to_remove_count = io.read_var_int
    components_to_add = Hash(UInt32, DataComponent).new

    components_to_add_count.times do
      component_type = io.read_var_int
      # Read component data directly based on type (no size prefix)
      begin
        structured_component = DataComponent.create_component(component_type, io)
        components_to_add[component_type] = structured_component
      rescue ex
        # Log error and create empty unknown component as fallback
        Log.warn { "Failed to parse component type #{component_type}: #{ex}" }
        components_to_add[component_type] = DataComponents::Unknown.new(Bytes.new(0))
      end
    end

    # Read components to remove
    components_to_remove = Set(UInt32).new
    components_to_remove_count.times do
      component_type = io.read_var_int
      components_to_remove.add(component_type)
    end

    new(count, item_id_int, components_to_add, components_to_remove)
  end

  def write(io)
    io.write_var_int count
    return if count == 0 # Empty slot

    io.write_var_int item_id_int

    # Write components to add count
    io.write_var_int components_to_add.size
    # Write components to remove count
    io.write_var_int components_to_remove.size

    components_to_add.each do |component_type, component|
      io.write_var_int component_type
      # Write component data directly (no size prefix)
      component.write(io)
    end

    # Write components to remove
    components_to_remove.each do |component_type|
      io.write_var_int component_type
    end
  end

  def empty?
    count == 0
  end

  def present?
    count > 0
  end

  def full?
    count >= max_stack_size
  end

  def item : MCData::Item
    @cached_item ||= MCData::DEFAULT.items.find { |item| item.id == item_id_int } ||
      raise "Unknown item ID: #{item_id_int}"
  end

  def damage
    damage_component = components_to_add[DataComponentType::Damage.value]?
    return 0 unless damage_component.is_a?(DataComponents::Damage)
    damage_component.value.to_i32
  end

  def durability
    max_durability - damage
  end

  def max_durability
    max_damage_component = components_to_add[DataComponentType::MaxDamage.value]?
    if max_damage_component.is_a?(DataComponents::MaxDamage)
      max_damage_component.value.to_u16
    else
      item.max_durability || 0_u16
    end
  end

  def max_stack_size
    max_stack_component = components_to_add[DataComponentType::MaxStackSize.value]?
    if max_stack_component.is_a?(DataComponents::MaxStackSize)
      max_stack_component.value.to_u8
    else
      item.stack_size
    end
  end

  def efficiency
    enchantments["efficiency"]? || 0
  end

  def enchantments
    enchant_component = components_to_add[DataComponentType::Enchantments.value]?
    return Hash(String, Int8 | Int16 | Int32 | Int64 | UInt8).new unless enchant_component.is_a?(DataComponents::Enchantments)

    result = Hash(String, Int8 | Int16 | Int32 | Int64 | UInt8).new
    enchant_component.enchantments.each do |type_id, level|
      # Convert type_id to string name using the mapping constant
      enchant_name = ENCHANTMENT_TYPE_MAP[type_id] || "enchant_#{type_id}"
      result[enchant_name] = level.to_i32
    end
    result
  end

  def enchanted? : Bool
    !enchantments.empty?
  end

  def needs_repair? : Bool
    worth_repairing? && durability < 12
  end

  def worth_repairing? : Bool
    return false unless name.includes?("diamond") || name.includes?("netherite")

    enchanted? && repair_cost <= 31
  end

  def repair_cost : Int32
    repair_component = components_to_add[DataComponentType::RepairCost.value]?
    return 0 unless repair_component.is_a?(DataComponents::RepairCost)
    repair_component.cost.to_i32
  end

  def name : String
    item.name
  end

  def matches?(item_id_int : UInt32)
    self.item_id_int == item_id_int
  end

  def matches?(name : String)
    self.name == name
  end

  def matches?(spec : Rosegold::WindowSlot -> _)
    spec.call self
  end

  def matches?(&)
    yield self
  end

  def decrement
    return if count <= 0
    @count -= 1
    make_empty if count <= 0
  end

  def make_empty
    @count = 0_u32
    @item_id_int = 0_u32
    @components_to_add.clear
    @components_to_remove.clear
  end

  def swap_with(other)
    tmp = @item_id_int
    @item_id_int = other.item_id_int
    other.item_id_int = tmp

    tmp = @count
    @count = other.count
    other.count = tmp

    tmp = @components_to_add
    @components_to_add = other.components_to_add
    other.components_to_add = tmp

    tmp = @components_to_remove
    @components_to_remove = other.components_to_remove
    other.components_to_remove = tmp
  end

  def edible? : Bool
    [
      "apple", "baked_potato", "beef", "beetroot", "beetroot_soup", "bread", "carrot",
      "chicken", "chorus_fruit", "cod", "cooked_beef", "cooked_chicken", "cooked_cod",
      "cooked_mutton", "cooked_porkchop", "cooked_rabbit", "cooked_salmon", "cookie",
      "dried_kelp", "enchanted_golden_apple", "golden_apple", "golden_carrot",
      "honey_bottle", "melon_slice", "mushroom_stew", "mutton", "poisonous_potato",
      "porkchop", "potato", "pufferfish", "pumpkin_pie", "rabbit", "rabbit_stew",
      "rotten_flesh", "salmon", "spider_eye", "suspicious_stew", "sweet_berries",
      "glow_berries", "tropical_fish",
    ].includes? name
  end

  def to_s(io)
    inspect io
  end
end

class Rosegold::WindowSlot < Rosegold::Slot
  property slot_number : Int32

  def initialize(@slot_number, slot)
    super slot.count, slot.item_id_int, slot.components_to_add, slot.components_to_remove
  end

  def ==(other : Rosegold::WindowSlot)
    other.slot_number == slot_number && other.item_id_int == item_id_int && other.count == count && other.components_to_add == components_to_add && other.components_to_remove == components_to_remove
  end
end

# Hashed slot format used in ClickContainer packet
class Rosegold::HashedSlot
  property has_item : Bool
  property item_id_int : UInt32
  property count : UInt32
  property components_to_add : Hash(UInt32, UInt32) # Component type -> CRC32 hash
  property components_to_remove : Set(UInt32)       # Component types to remove

  def initialize(@has_item = false, @item_id_int = 0_u32, @count = 0_u32, @components_to_add = Hash(UInt32, UInt32).new, @components_to_remove = Set(UInt32).new); end

  def self.from_slot(slot : Slot) : HashedSlot
    if slot.empty?
      new(false)
    else
      # Generate CRC32 hashes for components
      hashed_components = Hash(UInt32, UInt32).new
      slot.components_to_add.each do |component_type, component|
        # Serialize component to bytes and compute CRC32
        component_buffer = Minecraft::IO::Memory.new
        component.write(component_buffer)
        component_data = component_buffer.to_slice
        crc32_hash = Digest::CRC32.checksum(component_data)
        hashed_components[component_type] = crc32_hash
      end

      new(true, slot.item_id_int, slot.count, hashed_components, slot.components_to_remove)
    end
  end

  def self.from_window_slot(window_slot : WindowSlot) : HashedSlot
    from_slot(window_slot.as(Slot))
  end

  def write(io)
    io.write has_item
    return unless has_item

    io.write_var_int item_id_int
    io.write_var_int count

    # Write components to add
    io.write_var_int components_to_add.size
    components_to_add.each do |component_type, hash|
      io.write_var_int component_type
      io.write hash # Write CRC32 hash as Int (4 bytes)
    end

    # Write components to remove
    io.write_var_int components_to_remove.size
    components_to_remove.each do |component_type|
      io.write_var_int component_type
    end
  end

  def empty?
    !has_item
  end

  def present?
    has_item
  end
end
