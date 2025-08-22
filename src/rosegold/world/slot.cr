require "../../minecraft/nbt"
require "digest/crc32"
require "./mcdata"
require "../crc32c"

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
    when 8 # minecraft:lore - Array of Text Components (NBT)
      DataComponents::Lore.read(io)
    when 9 # minecraft:rarity - VarInt enum
      DataComponents::Rarity.read(io)
    when 10 # minecraft:enchantments - Complex structure
      DataComponents::Enchantments.read(io)
    when 13 # minecraft:attribute_modifiers - Complex structure
      DataComponents::AttributeModifiers.read(io)
    when 15 # minecraft:tooltip_display - Hide all or parts of the item tooltip
      DataComponents::TooltipDisplay.read(io)
    when 16 # minecraft:repair_cost - VarInt
      DataComponents::RepairCost.read(io)
    when 27 # minecraft:enchantable - VarInt
      DataComponents::Enchantable.read(io)
    when 17 # minecraft:creative_slot_lock - no fields
      DataComponents::CreativeSlotLock.read(io)
    when 18 # minecraft:enchantment_glint_override - Boolean
      DataComponents::EnchantmentGlintOverride.read(io)
    when 36 # minecraft:map_color - Int
      DataComponents::MapColor.read(io)
    when 37 # minecraft:map_id - The ID of the map (VarInt)
      DataComponents::MapId.read(io)
    when 39 # minecraft:map_post_processing - VarInt enum
      DataComponents::MapPostProcessing.read(io)
    when 42 # minecraft:potion_contents - Visual and effects of a potion item
      DataComponents::PotionContents.read(io)
    when 47 # minecraft:trim - Armor's trim pattern and color
      DataComponents::Trim.read(io)
    when 63 # minecraft:banner_patterns - Array of banner pattern layers
      DataComponents::BannerPatterns.read(io)
    else
      raise "Unknown data component type: #{component_type}"
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
    io.write value
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
    io.write value
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
    io.write value
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
    io.write cost
  end
end

# Component for attribute modifiers (complex structure)
class Rosegold::DataComponents::AttributeModifiers < Rosegold::DataComponent
  property modifiers : Array(AttributeModifier)

  struct AttributeModifier
    property attribute_id : UInt32
    property modifier_id : String
    property value : Float64
    property operation : UInt32
    property slot : UInt32

    def initialize(@attribute_id : UInt32, @modifier_id : String, @value : Float64, @operation : UInt32, @slot : UInt32)
    end
  end

  def initialize(@modifiers : Array(AttributeModifier) = [] of AttributeModifier); end

  def self.read(io) : self
    modifier_count = io.read_var_int
    modifiers = Array(AttributeModifier).new
    modifier_count.times do |_|
      attribute_id = io.read_var_int
      modifier_id = io.read_var_string
      value = io.read_double
      operation = io.read_var_int
      slot = io.read_var_int

      # orphaned random byte causing misalignment, means nothing
      io.read_byte

      modifiers << AttributeModifier.new(attribute_id, modifier_id, value, operation, slot)
    end

    new(modifiers)
  end

  def write(io) : Nil
    io.write modifiers.size
    modifiers.each do |modifier|
      io.write modifier.attribute_id
      io.write modifier.modifier_id
      io.write modifier.value
      io.write modifier.operation
      io.write modifier.slot
    end
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
    io.write enchantments.size
    enchantments.each do |type_id, level|
      io.write type_id
      io.write level
    end
  end
end

# Component for custom name (Text Component)
class Rosegold::DataComponents::CustomName < Rosegold::DataComponent
  property value : String

  def initialize(@value : String); end

  def self.read(io) : self
    # Read as NBT Text Component
    nbt = io.read_nbt_unamed
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
    # Read NBT compound using the standard NBT reading approach
    # The CustomData component contains a full NBT compound tag
    nbt_data = io.read_nbt_unamed
    new(nbt_data)
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
    text_component = TextComponent.read(io)
    new(text_component.to_s)
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
    io.write model
  end
end

class Rosegold::DataComponents::Lore < Rosegold::DataComponent
  property lore : Array(String) # Array of Text Components

  def initialize(@lore : Array(String) = [] of String); end

  def self.read(io) : self
    lore_count = io.read_var_int
    lore = Array(String).new
    lore_count.times do
      nbt = io.read_nbt_unamed

      lore_text = case nbt
                  when Minecraft::NBT::StringTag
                    nbt.value
                  when Minecraft::NBT::CompoundTag
                    text = nbt["text"]?.try(&.as(Minecraft::NBT::StringTag).value) || ""
                    extra_text = ""
                    if extra = nbt["extra"]?
                      if extra.is_a?(Minecraft::NBT::ListTag)
                        extra.value.each do |item|
                          if item.is_a?(Minecraft::NBT::CompoundTag)
                            extra_text += item["text"]?.try(&.as(Minecraft::NBT::StringTag).value) || ""
                          end
                        end
                      end
                    end
                    text + extra_text
                  else
                    "Unknown"
                  end
      lore << lore_text
    end
    new(lore)
  end

  def write(io) : Nil
    io.write lore.size
    lore.each do |text|
      io.write Minecraft::NBT::StringTag.new(text)
    end
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
    io.write rarity
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

# Component for tooltip_display (Hide all or parts of the item tooltip)
class Rosegold::DataComponents::TooltipDisplay < Rosegold::DataComponent
  property hide_tooltip : Bool
  property hidden_components : Array(UInt32)

  def initialize(@hide_tooltip : Bool, @hidden_components : Array(UInt32) = [] of UInt32); end

  def self.read(io) : self
    hide_tooltip = io.read_bool

    # Read hidden components array (prefixed with count)
    hidden_count = io.read_var_int
    hidden_components = Array(UInt32).new
    hidden_count.times do
      component_id = io.read_var_int
      hidden_components << component_id
    end

    new(hide_tooltip, hidden_components)
  end

  def write(io) : Nil
    io.write hide_tooltip
    io.write hidden_components.size
    hidden_components.each do |component_id|
      io.write component_id
    end
  end
end

# Component for enchantable (VarInt)
class Rosegold::DataComponents::Enchantable < Rosegold::DataComponent
  property value : UInt32

  def initialize(@value : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write value
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

# Component for map_color (RGB color as Int)
class Rosegold::DataComponents::MapColor < Rosegold::DataComponent
  property color : Int32

  def initialize(@color : Int32); end

  def self.read(io) : self
    new(io.read_int)
  end

  def write(io) : Nil
    io.write color
  end
end

# Component for map_id (VarInt) - The ID of the map
class Rosegold::DataComponents::MapId < Rosegold::DataComponent
  property id : UInt32

  def initialize(@id : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write id
  end
end

# Component for trim (Armor's trim pattern and color)
class Rosegold::DataComponents::Trim < Rosegold::DataComponent
  property material : TrimMaterial
  property pattern : TrimPattern

  def initialize(@material : TrimMaterial, @pattern : TrimPattern); end

  def self.read(io) : self
    material = TrimMaterial.read(io)
    pattern = TrimPattern.read(io)
    new(material, pattern)
  end

  def write(io) : Nil
    material.write(io)
    pattern.write(io)
  end

  # ID or TrimMaterial - either registry ID or inline definition
  struct TrimMaterial
    property registry_id : UInt32?
    property inline_data : InlineTrimMaterial?

    def initialize(@registry_id : UInt32?, @inline_data : InlineTrimMaterial?)
    end

    def self.read(io) : self
      id = io.read_var_int
      if id == 0
        # Inline definition (not implemented yet - would need full material structure)
        inline_data = InlineTrimMaterial.read(io)
        new(nil, inline_data)
      else
        # Registry ID (id - 1 since 0 means inline)
        new(id - 1, nil)
      end
    end

    def write(io) : Nil
      if registry_id
        if id = registry_id
          io.write(id + 1)
        end
      else
        io.write(0_u32)
        if data = inline_data
          data.write(io)
        end
      end
    end

    # Placeholder for inline trim material data
    struct InlineTrimMaterial
      property asset_name : String
      property ingredient : UInt32
      property item_model_index : Float32
      property override_armor_materials : Hash(String, String)
      property description : String

      def initialize(@asset_name = "", @ingredient = 0_u32, @item_model_index = 0.0_f32, @override_armor_materials = Hash(String, String).new, @description = "")
      end

      def self.read(io) : self
        # Read trim material structure
        asset_name = io.read_var_string
        ingredient = io.read_var_int
        item_model_index = io.read_float

        # Override armor materials (map of string->string)
        material_count = io.read_var_int
        override_materials = Hash(String, String).new
        material_count.times do
          key = io.read_var_string
          value = io.read_var_string
          override_materials[key] = value
        end

        # Description as Text Component
        description_component = TextComponent.read(io)
        description = description_component.to_s

        new(asset_name, ingredient, item_model_index, override_materials, description)
      end

      def write(io) : Nil
        io.write asset_name
        io.write ingredient
        io.write item_model_index
        io.write override_armor_materials.size
        override_armor_materials.each do |key, value|
          io.write key
          io.write value
        end
        io.write Minecraft::NBT::StringTag.new(description)
      end
    end
  end

  # ID or TrimPattern - either registry ID or inline definition
  struct TrimPattern
    property registry_id : UInt32?
    property inline_data : InlineTrimPattern?

    def initialize(@registry_id : UInt32?, @inline_data : InlineTrimPattern?)
    end

    def self.read(io) : self
      id = io.read_var_int
      if id == 0
        # Inline definition
        inline_data = InlineTrimPattern.read(io)
        new(nil, inline_data)
      else
        # Registry ID (id - 1 since 0 means inline)
        new(id - 1, nil)
      end
    end

    def write(io) : Nil
      if registry_id
        if id = registry_id
          io.write(id + 1)
        end
      else
        io.write(0_u32)
        if data = inline_data
          data.write(io)
        end
      end
    end

    # Inline trim pattern structure
    struct InlineTrimPattern
      property asset_name : String
      property template_item : UInt32
      property description : String
      property decal : Bool

      def initialize(@asset_name : String, @template_item : UInt32, @description : String, @decal : Bool)
      end

      def self.read(io) : self
        asset_name = io.read_var_string
        template_item = io.read_var_int
        # Description is a Text Component - for now read as simple string
        description_component = TextComponent.read(io)
        description = description_component.to_s
        decal = io.read_bool
        new(asset_name, template_item, description, decal)
      end

      def write(io) : Nil
        io.write asset_name
        io.write template_item
        io.write Minecraft::NBT::StringTag.new(description)
        io.write decal
      end
    end
  end
end

# Component for map_post_processing (VarInt enum)
class Rosegold::DataComponents::MapPostProcessing < Rosegold::DataComponent
  property processing_type : UInt32

  def initialize(@processing_type : UInt32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write processing_type
  end
end

# Component for banner_patterns (Array of banner pattern layers)
class Rosegold::DataComponents::BannerPatterns < Rosegold::DataComponent
  property layers : Array(BannerPatternLayer)

  struct BannerPatternLayer
    property pattern_type : UInt32
    property asset_id : String?
    property translation_key : String?
    property color : UInt32

    def initialize(@pattern_type : UInt32, @asset_id : String?, @translation_key : String?, @color : UInt32)
    end
  end

  def initialize(@layers : Array(BannerPatternLayer) = [] of BannerPatternLayer); end

  def self.read(io) : self
    layer_count = io.read_var_int
    layers = Array(BannerPatternLayer).new
    layer_count.times do
      pattern_type = io.read_var_int

      # Asset ID and Translation Key are only present when pattern_type is 0
      asset_id = nil
      translation_key = nil
      if pattern_type == 0
        asset_id = io.read_var_string
        translation_key = io.read_var_string
      end

      # Color is a Dye Color (VarInt enum)
      color = io.read_var_int

      layers << BannerPatternLayer.new(pattern_type, asset_id, translation_key, color)
    end
    new(layers)
  end

  def write(io) : Nil
    io.write layers.size
    layers.each do |layer|
      io.write layer.pattern_type

      # Write asset_id and translation_key only if pattern_type is 0
      if layer.pattern_type == 0
        io.write layer.asset_id.not_nil!        # ameba:disable Lint/NotNil
        io.write layer.translation_key.not_nil! # ameba:disable Lint/NotNil
      end

      io.write layer.color
    end
  end
end

# Component for potion contents (visual and effects of a potion item)
class Rosegold::DataComponents::PotionContents < Rosegold::DataComponent
  property has_potion_id : Bool
  property potion_id : UInt32?
  property has_custom_color : Bool
  property custom_color : UInt32?
  property custom_effects : Array(PotionEffect)
  property custom_name : String

  def initialize(@has_potion_id = false, @potion_id = nil, @has_custom_color = false, @custom_color = nil, @custom_effects = [] of PotionEffect, @custom_name = "")
  end

  def self.read(io) : PotionContents
    has_potion_id = io.read_bool
    potion_id = has_potion_id ? io.read_var_int : nil

    has_custom_color = io.read_bool
    custom_color = has_custom_color ? io.read_int.to_u32 : nil

    # Read custom effects array
    effects_count = io.read_var_int
    custom_effects = [] of PotionEffect
    effects_count.times do
      custom_effects << PotionEffect.read(io)
    end

    custom_name = io.read_var_string

    new(has_potion_id, potion_id, has_custom_color, custom_color, custom_effects, custom_name)
  end

  def write(io) : Nil
    io.write has_potion_id
    if has_potion_id
      io.write potion_id.not_nil! # ameba:disable Lint/NotNil
    end

    io.write has_custom_color
    if has_custom_color
      io.write_full custom_color.not_nil! # ameba:disable Lint/NotNil
    end

    # Write custom effects array
    io.write custom_effects.size
    custom_effects.each do |effect|
      effect.write(io)
    end

    io.write custom_name
  end

  # Potion effect structure
  class PotionEffect
    property type_id : UInt32
    property amplifier : UInt32
    property duration : Int32
    property ambient : Bool
    property show_particles : Bool
    property show_icon : Bool
    property has_hidden_effect : Bool
    property hidden_effect : PotionEffect?

    def initialize(@type_id, @amplifier, @duration, @ambient = false, @show_particles = true, @show_icon = true, @has_hidden_effect = false, @hidden_effect = nil)
    end

    def self.read(io) : PotionEffect
      type_id = io.read_var_int
      amplifier = io.read_var_int
      duration = io.read_var_int.to_i32
      ambient = io.read_bool
      show_particles = io.read_bool
      show_icon = io.read_bool
      has_hidden_effect = io.read_bool
      hidden_effect = has_hidden_effect ? PotionEffect.read(io) : nil

      new(type_id, amplifier, duration, ambient, show_particles, show_icon, has_hidden_effect, hidden_effect)
    end

    def write(io) : Nil
      io.write type_id
      io.write amplifier
      io.write duration
      io.write ambient
      io.write show_particles
      io.write show_icon
      io.write has_hidden_effect
      if has_hidden_effect
        hidden_effect.not_nil!.write(io) # ameba:disable Lint/NotNil
      end
    end
  end
end

# Component for dyed_color (RGB color as Int)
class Rosegold::DataComponents::DyedColor < Rosegold::DataComponent
  property color : Int32

  def initialize(@color : Int32); end

  def self.read(io) : self
    new(io.read_int)
  end

  def write(io) : Nil
    io.write color
  end
end

class Rosegold::Slot
  property count : UInt32
  property components_to_add : Hash(UInt32, DataComponent) # Component type -> structured component
  property components_to_remove : Set(UInt32)              # Component types to remove

  @cached_item : MCData::Item?
  @item_id_int : UInt32

  def item_id_int
    @item_id_int
  end

  def item_id_int=(value : UInt32)
    if @item_id_int != value
      @item_id_int = value
      @cached_item = nil
    end
  end

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
      structured_component = DataComponent.create_component(component_type, io)
      components_to_add[component_type] = structured_component
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
    io.write count
    return if count == 0 # Empty slot

    io.write item_id_int

    # Write components to add count
    io.write components_to_add.size
    # Write components to remove count
    io.write components_to_remove.size

    components_to_add.each do |component_type, component|
      io.write component_type
      # Write component data directly (no size prefix)
      component.write(io)
    end

    # Write components to remove
    components_to_remove.each do |component_type|
      io.write component_type
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
      # Convert type_id to string name using MCData
      enchantment = MCData::DEFAULT.enchantments.find { |e| e.id == type_id }
      enchant_name = enchantment ? enchantment.name : "enchant_#{type_id}"
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
    self.item_id_int = 0_u32
    @components_to_add.clear
    @components_to_remove.clear
  end

  def swap_with(other)
    tmp = self.item_id_int
    self.item_id_int = other.item_id_int
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
        component_buffer = Minecraft::IO::Memory.new
        component_buffer.write component_type
        component.write(component_buffer)
        component_data = component_buffer.to_slice
        crc32_hash = CRC32C.checksum(component_data)
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

    io.write item_id_int
    io.write count

    # Write components to add
    io.write components_to_add.size
    components_to_add.each do |component_type, hash|
      io.write component_type
      io.write_full hash.to_u32 # Write CRC32 hash as full 4 bytes (not VarInt)
    end

    # Write components to remove
    io.write components_to_remove.size
    components_to_remove.each do |component_type|
      io.write component_type
    end
  end

  def empty?
    !has_item
  end

  def present?
    has_item
  end
end
