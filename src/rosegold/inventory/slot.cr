require "../../minecraft/nbt"
require "digest/crc32"
require "../world/mcdata"
require "../crc32c"
require "../models/text_component"

# Version-specific component ID → name mappings
module Rosegold::DataComponentTypes
  # Protocol 772 (MC 1.21.8) — 96 component types
  PROTOCOL_772 = {
    0_u32 => "custom_data", 1_u32 => "max_stack_size", 2_u32 => "max_damage",
    3_u32 => "damage", 4_u32 => "unbreakable", 5_u32 => "custom_name",
    6_u32 => "item_name", 7_u32 => "item_model", 8_u32 => "lore",
    9_u32 => "rarity", 10_u32 => "enchantments", 11_u32 => "can_place_on",
    12_u32 => "can_break", 13_u32 => "attribute_modifiers", 14_u32 => "custom_model_data",
    15_u32 => "tooltip_display", 16_u32 => "repair_cost", 17_u32 => "creative_slot_lock",
    18_u32 => "enchantment_glint_override", 19_u32 => "intangible_projectile",
    20_u32 => "food", 21_u32 => "consumable", 22_u32 => "use_remainder",
    23_u32 => "use_cooldown", 24_u32 => "damage_resistant", 25_u32 => "tool",
    26_u32 => "weapon", 27_u32 => "enchantable", 28_u32 => "equippable",
    29_u32 => "repairable", 30_u32 => "glider", 31_u32 => "tooltip_style",
    32_u32 => "death_protection", 33_u32 => "blocks_attacks",
    34_u32 => "stored_enchantments", 35_u32 => "dyed_color", 36_u32 => "map_color",
    37_u32 => "map_id", 38_u32 => "map_decorations", 39_u32 => "map_post_processing",
    40_u32 => "potion_duration_scale", 41_u32 => "charged_projectiles",
    42_u32 => "bundle_contents", 43_u32 => "potion_contents",
    44_u32 => "suspicious_stew_effects", 45_u32 => "writable_book_content",
    46_u32 => "written_book_content", 47_u32 => "trim", 48_u32 => "debug_stick_state",
    49_u32 => "entity_data", 50_u32 => "bucket_entity_data",
    51_u32 => "block_entity_data", 52_u32 => "instrument",
    53_u32 => "provides_trim_material", 54_u32 => "ominous_bottle_amplifier",
    55_u32 => "jukebox_playable", 56_u32 => "provides_banner_patterns",
    57_u32 => "recipes", 58_u32 => "lodestone_tracker", 59_u32 => "firework_explosion",
    60_u32 => "fireworks", 61_u32 => "profile", 62_u32 => "note_block_sound",
    63_u32 => "banner_patterns", 64_u32 => "base_color", 65_u32 => "pot_decorations",
    66_u32 => "container", 67_u32 => "block_state", 68_u32 => "bees",
    69_u32 => "lock", 70_u32 => "container_loot", 71_u32 => "break_sound",
    72_u32 => "villager/variant", 73_u32 => "wolf/variant", 74_u32 => "wolf/sound_variant",
    75_u32 => "wolf/collar", 76_u32 => "fox/variant", 77_u32 => "salmon/size",
    78_u32 => "parrot/variant", 79_u32 => "tropical_fish/pattern",
    80_u32 => "tropical_fish/base_color", 81_u32 => "tropical_fish/pattern_color",
    82_u32 => "mooshroom/variant", 83_u32 => "rabbit/variant", 84_u32 => "pig/variant",
    85_u32 => "cow/variant", 86_u32 => "chicken/variant", 87_u32 => "frog/variant",
    88_u32 => "horse/variant", 89_u32 => "painting/variant",
    90_u32 => "llama/variant", 91_u32 => "axolotl/variant", 92_u32 => "cat/variant",
    93_u32 => "cat/collar", 94_u32 => "sheep/color", 95_u32 => "shulker/color",
  }

  # Protocol 774 (MC 1.21.11) — 104 component types
  PROTOCOL_774 = {
    0_u32 => "custom_data", 1_u32 => "max_stack_size", 2_u32 => "max_damage",
    3_u32 => "damage", 4_u32 => "unbreakable", 5_u32 => "use_effects",
    6_u32 => "custom_name", 7_u32 => "minimum_attack_charge", 8_u32 => "damage_type",
    9_u32 => "item_name", 10_u32 => "item_model", 11_u32 => "lore",
    12_u32 => "rarity", 13_u32 => "enchantments", 14_u32 => "can_place_on",
    15_u32 => "can_break", 16_u32 => "attribute_modifiers", 17_u32 => "custom_model_data",
    18_u32 => "tooltip_display", 19_u32 => "repair_cost", 20_u32 => "creative_slot_lock",
    21_u32 => "enchantment_glint_override", 22_u32 => "intangible_projectile",
    23_u32 => "food", 24_u32 => "consumable", 25_u32 => "use_remainder",
    26_u32 => "use_cooldown", 27_u32 => "damage_resistant", 28_u32 => "tool",
    29_u32 => "weapon", 30_u32 => "attack_range", 31_u32 => "enchantable",
    32_u32 => "equippable", 33_u32 => "repairable", 34_u32 => "glider",
    35_u32 => "tooltip_style", 36_u32 => "death_protection", 37_u32 => "blocks_attacks",
    38_u32 => "piercing_weapon", 39_u32 => "kinetic_weapon", 40_u32 => "swing_animation",
    41_u32 => "stored_enchantments", 42_u32 => "dyed_color", 43_u32 => "map_color",
    44_u32 => "map_id", 45_u32 => "map_decorations", 46_u32 => "map_post_processing",
    47_u32 => "charged_projectiles", 48_u32 => "bundle_contents",
    49_u32 => "potion_contents", 50_u32 => "potion_duration_scale",
    51_u32 => "suspicious_stew_effects", 52_u32 => "writable_book_content",
    53_u32 => "written_book_content", 54_u32 => "trim", 55_u32 => "debug_stick_state",
    56_u32 => "entity_data", 57_u32 => "bucket_entity_data",
    58_u32 => "block_entity_data", 59_u32 => "instrument",
    60_u32 => "provides_trim_material", 61_u32 => "ominous_bottle_amplifier",
    62_u32 => "jukebox_playable", 63_u32 => "provides_banner_patterns",
    64_u32 => "recipes", 65_u32 => "lodestone_tracker", 66_u32 => "firework_explosion",
    67_u32 => "fireworks", 68_u32 => "profile", 69_u32 => "note_block_sound",
    70_u32 => "banner_patterns", 71_u32 => "base_color", 72_u32 => "pot_decorations",
    73_u32 => "container", 74_u32 => "block_state", 75_u32 => "bees",
    76_u32 => "lock", 77_u32 => "container_loot", 78_u32 => "break_sound",
    79_u32 => "villager/variant", 80_u32 => "wolf/variant", 81_u32 => "wolf/sound_variant",
    82_u32 => "wolf/collar", 83_u32 => "fox/variant", 84_u32 => "salmon/size",
    85_u32 => "parrot/variant", 86_u32 => "tropical_fish/pattern",
    87_u32 => "tropical_fish/base_color", 88_u32 => "tropical_fish/pattern_color",
    89_u32 => "mooshroom/variant", 90_u32 => "rabbit/variant", 91_u32 => "pig/variant",
    92_u32 => "cow/variant", 93_u32 => "chicken/variant", 94_u32 => "zombie_nautilus/variant",
    95_u32 => "frog/variant", 96_u32 => "horse/variant", 97_u32 => "painting/variant",
    98_u32 => "llama/variant", 99_u32 => "axolotl/variant", 100_u32 => "cat/variant",
    101_u32 => "cat/collar", 102_u32 => "sheep/color", 103_u32 => "shulker/color",
  }

  # Protocol 775 (MC 26.1) — 110 component types (6 new: additional_trade_cost, dye, pig/sound_variant, cow/sound_variant, chicken/sound_variant, cat/sound_variant)
  PROTOCOL_775 = {
    0_u32 => "custom_data", 1_u32 => "max_stack_size", 2_u32 => "max_damage",
    3_u32 => "damage", 4_u32 => "unbreakable", 5_u32 => "use_effects",
    6_u32 => "custom_name", 7_u32 => "minimum_attack_charge", 8_u32 => "damage_type",
    9_u32 => "item_name", 10_u32 => "item_model", 11_u32 => "lore",
    12_u32 => "rarity", 13_u32 => "enchantments", 14_u32 => "can_place_on",
    15_u32 => "can_break", 16_u32 => "attribute_modifiers", 17_u32 => "custom_model_data",
    18_u32 => "tooltip_display", 19_u32 => "repair_cost", 20_u32 => "creative_slot_lock",
    21_u32 => "enchantment_glint_override", 22_u32 => "intangible_projectile",
    23_u32 => "food", 24_u32 => "consumable", 25_u32 => "use_remainder",
    26_u32 => "use_cooldown", 27_u32 => "damage_resistant", 28_u32 => "tool",
    29_u32 => "weapon", 30_u32 => "attack_range", 31_u32 => "enchantable",
    32_u32 => "equippable", 33_u32 => "repairable", 34_u32 => "glider",
    35_u32 => "tooltip_style", 36_u32 => "death_protection", 37_u32 => "blocks_attacks",
    38_u32 => "piercing_weapon", 39_u32 => "kinetic_weapon", 40_u32 => "swing_animation",
    41_u32 => "additional_trade_cost", # NEW in 26.1
    42_u32 => "stored_enchantments",
    43_u32 => "dye", # NEW in 26.1
    44_u32 => "dyed_color", 45_u32 => "map_color",
    46_u32 => "map_id", 47_u32 => "map_decorations", 48_u32 => "map_post_processing",
    49_u32 => "charged_projectiles", 50_u32 => "bundle_contents",
    51_u32 => "potion_contents", 52_u32 => "potion_duration_scale",
    53_u32 => "suspicious_stew_effects", 54_u32 => "writable_book_content",
    55_u32 => "written_book_content", 56_u32 => "trim", 57_u32 => "debug_stick_state",
    58_u32 => "entity_data", 59_u32 => "bucket_entity_data",
    60_u32 => "block_entity_data", 61_u32 => "instrument",
    62_u32 => "provides_trim_material", 63_u32 => "ominous_bottle_amplifier",
    64_u32 => "jukebox_playable", 65_u32 => "provides_banner_patterns",
    66_u32 => "recipes", 67_u32 => "lodestone_tracker", 68_u32 => "firework_explosion",
    69_u32 => "fireworks", 70_u32 => "profile", 71_u32 => "note_block_sound",
    72_u32 => "banner_patterns", 73_u32 => "base_color", 74_u32 => "pot_decorations",
    75_u32 => "container", 76_u32 => "block_state", 77_u32 => "bees",
    78_u32 => "lock", 79_u32 => "container_loot", 80_u32 => "break_sound",
    81_u32 => "villager/variant", 82_u32 => "wolf/variant", 83_u32 => "wolf/sound_variant",
    84_u32 => "wolf/collar", 85_u32 => "fox/variant", 86_u32 => "salmon/size",
    87_u32 => "parrot/variant", 88_u32 => "tropical_fish/pattern",
    89_u32 => "tropical_fish/base_color", 90_u32 => "tropical_fish/pattern_color",
    91_u32 => "mooshroom/variant", 92_u32 => "rabbit/variant", 93_u32 => "pig/variant",
    94_u32 => "pig/sound_variant", # NEW in 26.1
    95_u32 => "cow/variant",
    96_u32 => "cow/sound_variant", # NEW in 26.1
    97_u32 => "chicken/variant",
    98_u32 => "chicken/sound_variant", # NEW in 26.1
    99_u32 => "zombie_nautilus/variant",
    100_u32 => "frog/variant", 101_u32 => "horse/variant", 102_u32 => "painting/variant",
    103_u32 => "llama/variant", 104_u32 => "axolotl/variant", 105_u32 => "cat/variant",
    106_u32 => "cat/sound_variant", # NEW in 26.1
    107_u32 => "cat/collar", 108_u32 => "sheep/color", 109_u32 => "shulker/color",
  }

  PROTOCOL_MAP = {
    772_u32 => PROTOCOL_772,
    774_u32 => PROTOCOL_774,
    775_u32 => PROTOCOL_775,
  }

  def self.name_for(component_type : UInt32, protocol_version : UInt32) : String?
    if mapping = PROTOCOL_MAP[protocol_version]?
      mapping[component_type]?
    else
      PROTOCOL_774[component_type]?
    end
  end

  def self.id_for(name : String, protocol_version : UInt32) : UInt32?
    mapping = PROTOCOL_MAP[protocol_version]? || PROTOCOL_774
    mapping.each do |component_id, component_name|
      return component_id if component_name == name
    end
    nil
  end
end

# Raised when an unknown/modded data component is encountered and can't be skipped
class Rosegold::UnknownComponentError < Exception; end

# Base class for data components
abstract class Rosegold::DataComponent
  abstract def write(io) : Nil

  # Factory method to create structured components by name-based dispatch
  def self.create_component(component_type : UInt32, io) : DataComponent
    name = DataComponentTypes.name_for(component_type, Client.protocol_version)
    create_component_by_name(name, component_type, io)
  end

  def self.create_component_by_name(name : String?, component_type : UInt32, io) : DataComponent
    case name
    when "custom_data"                then DataComponents::CustomData.read(io)
    when "max_stack_size"             then DataComponents::MaxStackSize.read(io)
    when "max_damage"                 then DataComponents::MaxDamage.read(io)
    when "damage"                     then DataComponents::Damage.read(io)
    when "unbreakable"                then DataComponents::Unbreakable.read(io)
    when "custom_name"                then DataComponents::CustomName.read(io)
    when "item_name"                  then DataComponents::ItemName.read(io)
    when "item_model"                 then DataComponents::ItemModel.read(io)
    when "lore"                       then DataComponents::Lore.read(io)
    when "rarity"                     then DataComponents::Rarity.read(io)
    when "enchantments"               then DataComponents::Enchantments.read(io)
    when "attribute_modifiers"        then DataComponents::AttributeModifiers.read(io)
    when "tooltip_display"            then DataComponents::TooltipDisplay.read(io)
    when "repair_cost"                then DataComponents::RepairCost.read(io)
    when "enchantable"                then DataComponents::Enchantable.read(io)
    when "creative_slot_lock"         then DataComponents::CreativeSlotLock.read(io)
    when "enchantment_glint_override" then DataComponents::EnchantmentGlintOverride.read(io)
    when "dyed_color"                 then DataComponents::DyedColor.read(io)
    when "map_color"                  then DataComponents::MapColor.read(io)
    when "map_id"                     then DataComponents::MapId.read(io)
    when "map_post_processing"        then DataComponents::MapPostProcessing.read(io)
    when "potion_contents"            then DataComponents::PotionContents.read(io)
    when "trim"                       then DataComponents::Trim.read(io)
    when "entity_data"
      Client.protocol_version >= 774_u32 ? DataComponents::TypedEntityData.read(io) : DataComponents::EntityData.read(io)
    when "banner_patterns"         then DataComponents::BannerPatterns.read(io)
    when "weapon"                  then DataComponents::Weapon.read(io)
    when "stored_enchantments"     then DataComponents::Enchantments.read(io)
    when "intangible_projectile"   then DataComponents::Unbreakable.read(io) # empty component
    when "food"                    then DataComponents::Food.read(io)
    when "consumable"              then DataComponents::Consumable.read(io)
    when "use_remainder"           then DataComponents::UseRemainder.read(io)
    when "use_cooldown"            then DataComponents::UseCooldown.read(io)
    when "damage_resistant"        then DataComponents::DamageResistant.read(io)
    when "tool"                    then DataComponents::Tool.read(io)
    when "equippable"              then DataComponents::Equippable.read(io)
    when "repairable"              then DataComponents::Repairable.read(io)
    when "glider"                  then DataComponents::Unbreakable.read(io) # empty component
    when "tooltip_style"           then DataComponents::TooltipStyle.read(io)
    when "death_protection"        then DataComponents::DeathProtection.read(io)
    when "blocks_attacks"          then DataComponents::BlocksAttacks.read(io)
    when "charged_projectiles"     then DataComponents::SlotList.read(io)
    when "bundle_contents"         then DataComponents::SlotList.read(io)
    when "potion_duration_scale"   then DataComponents::PotionDurationScale.read(io)
    when "suspicious_stew_effects" then DataComponents::SuspiciousStewEffects.read(io)
    when "writable_book_content"   then DataComponents::WritableBookContent.read(io)
    when "written_book_content"    then DataComponents::WrittenBookContent.read(io)
    when "bucket_entity_data"      then DataComponents::EntityData.read(io)
    when "block_entity_data"
      Client.protocol_version >= 774_u32 ? DataComponents::TypedEntityData.read(io) : DataComponents::EntityData.read(io)
    when "debug_stick_state"        then DataComponents::EntityData.read(io) # NBT compound
    when "map_decorations"          then DataComponents::EntityData.read(io) # NBT compound
    when "instrument"               then DataComponents::Instrument.read(io)
    when "provides_trim_material"   then DataComponents::ProvidesTrimMaterial.read(io)
    when "ominous_bottle_amplifier" then DataComponents::OminousBottleAmplifier.read(io)
    when "jukebox_playable"         then DataComponents::JukeboxPlayable.read(io)
    when "provides_banner_patterns" then DataComponents::ProvidesBannerPatterns.read(io)
    when "recipes"                  then DataComponents::Recipes.read(io)
    when "lodestone_tracker"        then DataComponents::LodestoneTracker.read(io)
    when "firework_explosion"       then DataComponents::FireworkExplosion.read(io)
    when "fireworks"                then DataComponents::Fireworks.read(io)
    when "profile"                  then DataComponents::Profile.read(io)
    when "note_block_sound"         then DataComponents::NoteBlockSound.read(io)
    when "base_color"               then DataComponents::BaseColor.read(io)
    when "pot_decorations"          then DataComponents::PotDecorations.read(io)
    when "container"                then DataComponents::Container.read(io)
    when "block_state"              then DataComponents::BlockState.read(io)
    when "bees"                     then DataComponents::Bees.read(io)
    when "lock"                     then DataComponents::Lock.read(io)
    when "container_loot"           then DataComponents::ContainerLoot.read(io)
    when "break_sound"              then DataComponents::BreakSound.read(io)
    when "can_place_on"             then DataComponents::BlockPredicates.read(io)
    when "can_break"                then DataComponents::BlockPredicates.read(io)
    when "custom_model_data"        then DataComponents::CustomModelData.read(io)
      # New 1.21.11 component types
    when "use_effects"           then DataComponents::UseEffects.read(io)
    when "minimum_attack_charge" then DataComponents::FloatComponent.read(io)
    when "damage_type"           then DataComponents::EitherHolderComponent.read(io)
    when "attack_range"          then DataComponents::AttackRange.read(io)
    when "piercing_weapon"       then DataComponents::PiercingWeapon.read(io)
    when "kinetic_weapon"        then DataComponents::KineticWeapon.read(io)
    when "swing_animation"       then DataComponents::SwingAnimation.read(io)
      # New 26.1 component types
    when "additional_trade_cost" then DataComponents::VarIntComponent.read(io)
    when "dye"                   then DataComponents::VarIntComponent.read(io)
      # Entity variant components (most are simple VarInt)
    when "villager/variant"            then DataComponents::VarIntComponent.read(io)
    when "wolf/variant"                then DataComponents::HolderComponent.read(io)
    when "wolf/sound_variant"          then DataComponents::HolderComponent.read(io)
    when "wolf/collar"                 then DataComponents::VarIntComponent.read(io)
    when "fox/variant"                 then DataComponents::VarIntComponent.read(io)
    when "salmon/size"                 then DataComponents::VarIntComponent.read(io)
    when "parrot/variant"              then DataComponents::VarIntComponent.read(io)
    when "tropical_fish/pattern"       then DataComponents::VarIntComponent.read(io)
    when "tropical_fish/base_color"    then DataComponents::VarIntComponent.read(io)
    when "tropical_fish/pattern_color" then DataComponents::VarIntComponent.read(io)
    when "mooshroom/variant"           then DataComponents::VarIntComponent.read(io)
    when "rabbit/variant"              then DataComponents::VarIntComponent.read(io)
    when "pig/variant"                 then DataComponents::HolderComponent.read(io)
    when "pig/sound_variant"           then DataComponents::HolderComponent.read(io)
    when "cow/variant"                 then DataComponents::HolderComponent.read(io)
    when "cow/sound_variant"           then DataComponents::HolderComponent.read(io)
    when "chicken/variant"
      Client.protocol_version >= 775_u32 ? DataComponents::VarIntComponent.read(io) : DataComponents::EitherHolderComponent.read(io)
    when "chicken/sound_variant" then DataComponents::HolderComponent.read(io)
    when "zombie_nautilus/variant"
      Client.protocol_version >= 775_u32 ? DataComponents::VarIntComponent.read(io) : DataComponents::EitherHolderComponent.read(io)
    when "frog/variant"      then DataComponents::HolderComponent.read(io)
    when "horse/variant"     then DataComponents::VarIntComponent.read(io)
    when "painting/variant"  then DataComponents::HolderComponent.read(io)
    when "llama/variant"     then DataComponents::VarIntComponent.read(io)
    when "axolotl/variant"   then DataComponents::VarIntComponent.read(io)
    when "cat/variant"       then DataComponents::HolderComponent.read(io)
    when "cat/collar"        then DataComponents::VarIntComponent.read(io)
    when "cat/sound_variant" then DataComponents::HolderComponent.read(io)
    when "sheep/color"       then DataComponents::VarIntComponent.read(io)
    when "shulker/color"     then DataComponents::VarIntComponent.read(io)
    else
      raise UnknownComponentError.new("Unknown data component type: #{component_type} (#{name || "unmapped"})")
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

  # Display = {type: VarInt, body: depends on type}
  # 0 = DEFAULT (no body), 1 = HIDDEN (no body), 2 = OVERRIDE (Text Component body)
  struct AttributeModifier
    property attribute_id : UInt32
    property modifier_id : String
    property value : Float64
    property operation : UInt32
    property slot : UInt32
    property display : UInt32
    property display_override : Rosegold::TextComponent?

    def initialize(@attribute_id : UInt32, @modifier_id : String, @value : Float64, @operation : UInt32, @slot : UInt32, @display : UInt32 = 0_u32, @display_override : Rosegold::TextComponent? = nil)
    end
  end

  def initialize(@modifiers : Array(AttributeModifier) = [] of AttributeModifier); end

  def self.read(io) : self
    modifier_count = io.read_var_int
    modifiers = Array(AttributeModifier).new
    modifier_count.times do
      attribute_id = io.read_var_int
      modifier_id = io.read_var_string
      value = io.read_double
      operation = io.read_var_int
      slot = io.read_var_int
      display = io.read_var_int
      display_override = display == 2 ? Rosegold::TextComponent.read(io) : nil
      modifiers << AttributeModifier.new(attribute_id, modifier_id, value, operation, slot, display, display_override)
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
      io.write modifier.display
      if modifier.display == 2
        override = modifier.display_override || Rosegold::TextComponent.new("")
        override.write(io)
      end
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
  property value : Rosegold::TextComponent

  def initialize(@value : Rosegold::TextComponent); end

  def self.new(text : String)
    new(Rosegold::TextComponent.new(text))
  end

  def self.read(io) : self
    new(Rosegold::TextComponent.read(io))
  end

  def write(io) : Nil
    value.write(io)
  end
end

# Component for custom data (NBT compound)
class Rosegold::DataComponents::CustomData < Rosegold::DataComponent
  property data : Minecraft::NBT::Tag

  def initialize(@data : Minecraft::NBT::Tag); end

  def self.read(io) : self
    new(io.read_nbt_unamed)
  end

  def write(io) : Nil
    io.write_byte data.tag_type
    data.write(io)
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
  property value : Rosegold::TextComponent

  def initialize(@value : Rosegold::TextComponent); end

  def self.new(text : String)
    new(Rosegold::TextComponent.new(text))
  end

  def self.read(io) : self
    new(Rosegold::TextComponent.read(io))
  end

  def write(io) : Nil
    value.write(io)
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
  property lore : Array(Rosegold::TextComponent)

  def initialize(@lore : Array(Rosegold::TextComponent) = [] of Rosegold::TextComponent); end

  def self.read(io) : self
    lore_count = io.read_var_int
    lines = Array(Rosegold::TextComponent).new(lore_count)
    lore_count.times { lines << Rosegold::TextComponent.read(io) }
    new(lines)
  end

  def write(io) : Nil
    io.write lore.size
    lore.each(&.write(io))
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
  property? hide_tooltip : Bool
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
    io.write hide_tooltip?
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
  property? has_glint : Bool

  def initialize(@has_glint : Bool); end

  def self.read(io) : self
    new(io.read_bool)
  end

  def write(io) : Nil
    io.write has_glint?
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
    io.write_full color
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
        new(nil, InlineTrimMaterial.read(io))
      else
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

    # Inline TrimMaterial (1.21.8/1.21.11 DIRECT_STREAM_CODEC):
    #   AssetInfo base  (String suffix)
    #   Map<ResourceKey<EquipmentAsset>, AssetInfo>  (prefixed array of (Identifier key, String suffix))
    #   TextComponent description
    struct InlineTrimMaterial
      property asset_name : String
      property override_armor_materials : Hash(String, String)
      property description : Rosegold::TextComponent

      def initialize(@asset_name = "", @override_armor_materials = Hash(String, String).new, @description = Rosegold::TextComponent.new(""))
      end

      def self.read(io) : self
        asset_name = io.read_var_string

        material_count = io.read_var_int
        override_materials = Hash(String, String).new
        material_count.times do
          key = io.read_var_string
          value = io.read_var_string
          override_materials[key] = value
        end

        description = Rosegold::TextComponent.read(io)
        new(asset_name, override_materials, description)
      end

      def write(io) : Nil
        io.write asset_name
        io.write override_armor_materials.size
        override_armor_materials.each do |key, value|
          io.write key
          io.write value
        end
        description.write(io)
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
        new(nil, InlineTrimPattern.read(io))
      else
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

    struct InlineTrimPattern
      property asset_name : String
      property template_item : UInt32
      property description : String
      property? decal : Bool

      def initialize(@asset_name : String, @template_item : UInt32, @description : String, @decal : Bool)
      end

      def self.read(io) : self
        asset_name = io.read_var_string
        template_item = io.read_var_int
        description = TextComponent.read(io).to_s
        decal = io.read_bool
        new(asset_name, template_item, description, decal)
      end

      def write(io) : Nil
        io.write asset_name
        io.write template_item
        io.write Minecraft::NBT::StringTag.new(description)
        io.write decal?
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

# Component for entity_data (NBT compound containing data for entity to be created)
class Rosegold::DataComponents::EntityData < Rosegold::DataComponent
  property data : Minecraft::NBT::Tag

  def initialize(@data : Minecraft::NBT::Tag); end

  def self.read(io) : self
    nbt_data = io.read_nbt_unamed
    new(nbt_data)
  end

  def write(io) : Nil
    io.write data
  end
end

# Component for potion contents (visual and effects of a potion item)
class Rosegold::DataComponents::PotionContents < Rosegold::DataComponent
  property? has_potion_id : Bool
  property potion_id : UInt32?
  property? has_custom_color : Bool
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

    has_custom_name = io.read_bool
    custom_name = has_custom_name ? io.read_var_string : ""

    new(has_potion_id, potion_id, has_custom_color, custom_color, custom_effects, custom_name)
  end

  def write(io) : Nil
    io.write has_potion_id?
    if has_potion_id?
      io.write potion_id.not_nil! # ameba:disable Lint/NotNil
    end

    io.write has_custom_color?
    if has_custom_color?
      io.write_full custom_color.not_nil! # ameba:disable Lint/NotNil
    end

    # Write custom effects array
    io.write custom_effects.size
    custom_effects.each do |effect|
      effect.write(io)
    end

    io.write !custom_name.empty?
    io.write custom_name unless custom_name.empty?
  end

  # Potion effect structure
  class PotionEffect
    property type_id : UInt32
    property amplifier : UInt32
    property duration : Int32
    property? ambient : Bool
    property? show_particles : Bool
    property? show_icon : Bool
    property? has_hidden_effect : Bool
    property hidden_effect : PotionEffect?

    def initialize(@type_id, @amplifier, @duration, @ambient = false, @show_particles = true, @show_icon = true, @has_hidden_effect = false, @hidden_effect = nil)
    end

    # Outer PotionEffect wire format = MobEffect Holder (VarInt) + Details.
    # Details recursion on `hidden_effect` is into Details only (no repeat of the
    # leading MobEffect VarInt). See MobEffectInstance.java Details.STREAM_CODEC.
    def self.read(io) : PotionEffect
      type_id = io.read_var_int
      read_details(io, type_id)
    end

    def self.read_details(io, type_id : UInt32) : PotionEffect
      amplifier = io.read_var_int
      duration = io.read_var_int.to_i32
      ambient = io.read_bool
      show_particles = io.read_bool
      show_icon = io.read_bool
      has_hidden_effect = io.read_bool
      # hidden_effect uses the *outer* effect's type_id; Details alone carries no type_id.
      hidden_effect = has_hidden_effect ? read_details(io, type_id) : nil

      new(type_id, amplifier, duration, ambient, show_particles, show_icon, has_hidden_effect, hidden_effect)
    end

    def write(io) : Nil
      io.write type_id
      write_details(io)
    end

    def write_details(io) : Nil
      io.write amplifier
      io.write duration
      io.write ambient?
      io.write show_particles?
      io.write show_icon?
      io.write has_hidden_effect?
      if has_hidden_effect?
        hidden_effect.not_nil!.write_details(io) # ameba:disable Lint/NotNil
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
    io.write_full color
  end
end

# Component for weapon (item damage per attack and disable blocking time)
class Rosegold::DataComponents::Weapon < Rosegold::DataComponent
  property item_damage_per_attack : UInt32
  property disable_blocking_for_seconds : Float32

  def initialize(@item_damage_per_attack : UInt32 = 1_u32, @disable_blocking_for_seconds : Float32 = 0.0_f32); end

  def self.read(io) : self
    item_damage_per_attack = io.read_var_int
    disable_blocking_for_seconds = io.read_float
    new(item_damage_per_attack, disable_blocking_for_seconds)
  end

  def write(io) : Nil
    io.write item_damage_per_attack
    io.write disable_blocking_for_seconds
  end
end

# SlotList - array of Slot (used by bundle_contents, charged_projectiles)
class Rosegold::DataComponents::SlotList < Rosegold::DataComponent
  property slots : Array(Rosegold::Slot)

  def initialize(@slots = [] of Rosegold::Slot); end

  def self.read(io) : self
    count = io.read_var_int
    slots = Array(Rosegold::Slot).new
    count.times { slots << Rosegold::Slot.read(io) }
    new(slots)
  end

  def write(io) : Nil
    io.write slots.size
    slots.each(&.write(io))
  end
end

# Food component
class Rosegold::DataComponents::Food < Rosegold::DataComponent
  property nutrition : UInt32
  property saturation : Float32
  property? can_always_eat : Bool

  def initialize(@nutrition = 0_u32, @saturation = 0.0_f32, @can_always_eat = false); end

  def self.read(io) : self
    new(io.read_var_int, io.read_float, io.read_bool)
  end

  def write(io) : Nil
    io.write nutrition
    io.write saturation
    io.write can_always_eat?
  end
end

# Consumable component
class Rosegold::DataComponents::Consumable < Rosegold::DataComponent
  property consume_seconds : Float32
  property animation : UInt32
  property sound : ConsumeSound
  property? has_particles : Bool
  property effects : Array(ConsumeEffect)

  struct ConsumeSound
    property sound_type : UInt32
    property sound_id : String?
    property? has_fixed_range : Bool
    property fixed_range : Float32?

    def initialize(@sound_type = 1_u32, @sound_id = nil, @has_fixed_range = false, @fixed_range = nil); end

    def self.read(io) : self
      sound_type = io.read_var_int
      if sound_type == 0
        sound_id = io.read_var_string
        has_fixed_range = io.read_bool
        fixed_range = has_fixed_range ? io.read_float : nil
        new(sound_type, sound_id, has_fixed_range, fixed_range)
      else
        new(sound_type, nil)
      end
    end

    def write(io) : Nil
      io.write sound_type
      if sound_type == 0
        io.write sound_id.not_nil! # ameba:disable Lint/NotNil
        io.write has_fixed_range?
        io.write fixed_range.not_nil! if has_fixed_range? # ameba:disable Lint/NotNil
      end
    end
  end

  struct ConsumeEffect
    property effect_type : UInt32
    property data : Bytes

    def initialize(@effect_type = 0_u32, @data = Bytes.empty); end
  end

  def initialize(@consume_seconds = 1.6_f32, @animation = 0_u32, @sound = ConsumeSound.new, @has_particles = true, @effects = [] of ConsumeEffect); end

  def self.read(io) : self
    consume_seconds = io.read_float
    animation = io.read_var_int
    sound = ConsumeSound.read(io)
    has_particles = io.read_bool
    effect_count = io.read_var_int
    effects = Array(ConsumeEffect).new
    effect_count.times do
      effect_type = io.read_var_int
      # Each effect type has different data; skip by reading based on type
      # For now, store type only (effects are complex and rarely needed)
      effects << ConsumeEffect.new(effect_type, read_consume_effect_data(io, effect_type))
    end
    new(consume_seconds, animation, sound, has_particles, effects)
  end

  protected def self.read_consume_effect_data(io, effect_type) : Bytes
    buf = Minecraft::IO::Memory.new
    case effect_type
    when 0 # apply_effects
      count = io.read_var_int
      buf.write count
      count.times do
        effect = Rosegold::DataComponents::PotionContents::PotionEffect.read(io)
        effect.write(buf)
      end
      prob = io.read_float
      buf.write prob
    when 1 # remove_effects
      # HolderSet of effects
      holder_type = io.read_var_int
      buf.write holder_type
      if holder_type == 0
        tag = io.read_var_string
        buf.write tag
      else
        count = holder_type - 1
        count.times { buf.write io.read_var_int }
      end
    when 2 # clear_all_effects - no data
    when 3 # teleport_randomly
      diameter = io.read_float
      buf.write diameter
    when 4 # play_sound
      sound = ConsumeSound.read(io)
      sound.write(buf)
    else
      raise "Unknown consume effect type #{effect_type}; cannot determine data length to skip"
    end
    buf.to_slice
  end

  def write(io) : Nil
    io.write consume_seconds
    io.write animation
    sound.write(io)
    io.write has_particles?
    io.write effects.size.to_u32
    effects.each do |effect|
      io.write effect.effect_type
      io.write effect.data
    end
  end
end

# UseRemainder - single Slot
class Rosegold::DataComponents::UseRemainder < Rosegold::DataComponent
  property slot : Rosegold::Slot

  def initialize(@slot); end

  def self.read(io) : self
    new(Rosegold::Slot.read(io))
  end

  def write(io) : Nil
    slot.write(io)
  end
end

# UseCooldown
class Rosegold::DataComponents::UseCooldown < Rosegold::DataComponent
  property seconds : Float32
  property? has_cooldown_group : Bool
  property cooldown_group : String?

  def initialize(@seconds = 0.0_f32, @has_cooldown_group = false, @cooldown_group = nil); end

  def self.read(io) : self
    seconds = io.read_float
    has_group = io.read_bool
    group = has_group ? io.read_var_string : nil
    new(seconds, has_group, group)
  end

  def write(io) : Nil
    io.write seconds
    io.write has_cooldown_group?
    io.write cooldown_group.not_nil! if has_cooldown_group? # ameba:disable Lint/NotNil
  end
end

# DamageResistant - single Identifier
class Rosegold::DataComponents::DamageResistant < Rosegold::DataComponent
  property tag : String

  def initialize(@tag = ""); end

  def self.read(io) : self
    new(io.read_var_string)
  end

  def write(io) : Nil
    io.write tag
  end
end

# Tool component
class Rosegold::DataComponents::Tool < Rosegold::DataComponent
  property rules : Array(ToolRule)
  property default_mining_speed : Float32
  property damage_per_block : UInt32
  property? can_destroy_blocks_in_creative : Bool

  struct ToolRule
    property blocks_type : UInt32
    property blocks_tag : String?
    property blocks_ids : Array(UInt32)?
    property? has_speed : Bool
    property speed : Float32?
    property? has_correct_for_drops : Bool
    property? correct_for_drops : Bool

    def initialize(@blocks_type = 0_u32, @blocks_tag = nil, @blocks_ids = nil,
                   @has_speed = false, @speed = nil,
                   @has_correct_for_drops = false, @correct_for_drops = false); end
  end

  def initialize(@rules = [] of ToolRule, @default_mining_speed = 1.0_f32, @damage_per_block = 1_u32, @can_destroy_blocks_in_creative = true); end

  def self.read(io) : self
    rule_count = io.read_var_int
    rules = Array(ToolRule).new
    rule_count.times do
      blocks_type = io.read_var_int
      blocks_tag = nil
      blocks_ids = nil
      if blocks_type == 0
        blocks_tag = io.read_var_string
      else
        count = blocks_type - 1
        blocks_ids = Array(UInt32).new
        count.times { blocks_ids << io.read_var_int }
      end
      has_speed = io.read_bool
      speed = has_speed ? io.read_float : nil
      has_correct = io.read_bool
      correct = has_correct ? io.read_bool : false
      rules << ToolRule.new(blocks_type, blocks_tag, blocks_ids, has_speed, speed, has_correct, correct)
    end
    default_mining_speed = io.read_float
    damage_per_block = io.read_var_int
    can_destroy = io.read_bool
    new(rules, default_mining_speed, damage_per_block, can_destroy)
  end

  def write(io) : Nil
    io.write rules.size
    rules.each do |rule|
      io.write rule.blocks_type
      if rule.blocks_type == 0
        if blocks_tag = rule.blocks_tag
          io.write blocks_tag
        end
      else
        if blocks_ids = rule.blocks_ids
          blocks_ids.each { |id| io.write id }
        end
      end
      io.write rule.has_speed?
      if rule.has_speed?
        if speed = rule.speed
          io.write speed
        end
      end
      io.write rule.has_correct_for_drops?
      io.write rule.correct_for_drops? if rule.has_correct_for_drops?
    end
    io.write default_mining_speed
    io.write damage_per_block
    io.write can_destroy_blocks_in_creative?
  end
end

# Equippable
class Rosegold::DataComponents::Equippable < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_var_int # slot
    equip_sound_type = capture.read_var_int
    if equip_sound_type == 0
      capture.read_var_string
      has_fixed_range = capture.read_bool
      capture.read_float if has_fixed_range
    end
    has_asset = capture.read_bool
    capture.read_var_string if has_asset
    has_camera_overlay = capture.read_bool
    capture.read_var_string if has_camera_overlay
    has_allowed = capture.read_bool
    if has_allowed
      allowed_entities_type = capture.read_var_int
      if allowed_entities_type == 0
        capture.read_var_string # tag
      else
        (allowed_entities_type - 1).times { capture.read_var_int }
      end
    end
    capture.read_bool # dispensable
    capture.read_bool # swappable
    capture.read_bool # damage_on_hurt
    capture.read_bool # equip_on_interact
    capture.read_bool # can_be_sheared
    # shearing_sound: Holder<SoundEvent>
    shearing_sound_type = capture.read_var_int
    if shearing_sound_type == 0
      capture.read_var_string
      has_fixed_range = capture.read_bool
      capture.read_float if has_fixed_range
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# Repairable - HolderSet of items
class Rosegold::DataComponents::Repairable < Rosegold::DataComponent
  property holder_type : UInt32
  property tag : String?
  property ids : Array(UInt32)?

  def initialize(@holder_type = 0_u32, @tag = nil, @ids = nil); end

  def self.read(io) : self
    holder_type = io.read_var_int
    if holder_type == 0
      new(holder_type, io.read_var_string, nil)
    else
      ids = Array(UInt32).new
      (holder_type - 1).times { ids << io.read_var_int }
      new(holder_type, nil, ids)
    end
  end

  def write(io) : Nil
    io.write holder_type
    if holder_type == 0
      if t = tag
        io.write t
      end
    else
      if id_list = ids
        id_list.each { |id| io.write id }
      end
    end
  end
end

# TooltipStyle - single Identifier
class Rosegold::DataComponents::TooltipStyle < Rosegold::DataComponent
  property style : String

  def initialize(@style = ""); end

  def self.read(io) : self
    new(io.read_var_string)
  end

  def write(io) : Nil
    io.write style
  end
end

# DeathProtection - list of consume effects
class Rosegold::DataComponents::DeathProtection < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times do
      effect_type = io.read_var_int
      Consumable.read_consume_effect_data(io, effect_type)
    end
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# BlocksAttacks
class Rosegold::DataComponents::BlocksAttacks < Rosegold::DataComponent
  property block_delay_seconds : Float32
  property disable_cooldown_scale : Float32
  property damage_reductions : Array(DamageReduction)
  property item_damage_threshold : Float32
  property item_damage_base : Float32
  property item_damage_factor : Float32
  property bypassed_by : String?

  # Optional HolderSet<DamageType>: bool has_type + (VarInt set_type + body).
  # set_type == 0 ⇒ tag name (Identifier string). set_type >= 1 ⇒ (set_type - 1) inline VarInt ids.
  struct DamageTypeHolderSet
    property set_type : UInt32
    property tag : String?
    property ids : Array(UInt32)

    def initialize(@set_type = 0_u32, @tag = nil, @ids = [] of UInt32); end

    def self.read(io) : self
      set_type = io.read_var_int
      if set_type == 0
        new(set_type, io.read_var_string, [] of UInt32)
      else
        ids = Array(UInt32).new(set_type - 1) { io.read_var_int }
        new(set_type, nil, ids)
      end
    end

    def write(io) : Nil
      io.write set_type
      if set_type == 0
        io.write(tag || "")
      else
        ids.each { |id| io.write id }
      end
    end
  end

  struct DamageReduction
    property horizontal_blocking_angle : Float32
    property type : DamageTypeHolderSet?
    property base_value : Float32
    property factor : Float32

    def initialize(@horizontal_blocking_angle = 0.0_f32, @type = nil, @base_value = 0.0_f32, @factor = 0.0_f32); end
  end

  property block_sound_raw : Bytes?
  property disable_sound_raw : Bytes?

  def initialize(@block_delay_seconds = 0.0_f32, @disable_cooldown_scale = 1.0_f32,
                 @damage_reductions = [] of DamageReduction,
                 @item_damage_threshold = 0.0_f32, @item_damage_base = 0.0_f32,
                 @item_damage_factor = 0.0_f32, @bypassed_by = nil,
                 @block_sound_raw = nil, @disable_sound_raw = nil); end

  def self.read(io) : self
    block_delay = io.read_float
    disable_cooldown = io.read_float
    reduction_count = io.read_var_int
    reductions = Array(DamageReduction).new
    reduction_count.times do
      angle = io.read_float
      has_type = io.read_bool
      type_set = has_type ? DamageTypeHolderSet.read(io) : nil
      base_val = io.read_float
      factor = io.read_float
      reductions << DamageReduction.new(angle, type_set, base_val, factor)
    end
    item_damage_threshold = io.read_float
    item_damage_base = io.read_float
    item_damage_factor = io.read_float
    bypassed_by = io.read_bool ? io.read_var_string : nil
    block_sound_raw = io.read_bool ? capture_sound_event_bytes(io) : nil
    disable_sound_raw = io.read_bool ? capture_sound_event_bytes(io) : nil
    new(block_delay, disable_cooldown, reductions, item_damage_threshold,
      item_damage_base, item_damage_factor, bypassed_by,
      block_sound_raw, disable_sound_raw)
  end

  private def self.capture_sound_event_bytes(io) : Bytes
    capture = Minecraft::IO::CaptureIO.new(io)
    SoundEventHelper.skip_sound_event_holder(capture)
    capture.buffer.to_slice.dup
  end

  def write(io) : Nil
    io.write block_delay_seconds
    io.write disable_cooldown_scale
    io.write damage_reductions.size
    damage_reductions.each do |reduction|
      io.write reduction.horizontal_blocking_angle
      io.write !reduction.type.nil?
      reduction.type.try &.write(io)
      io.write reduction.base_value
      io.write reduction.factor
    end
    io.write item_damage_threshold
    io.write item_damage_base
    io.write item_damage_factor
    if by = bypassed_by
      io.write true
      io.write by
    else
      io.write false
    end
    if raw = block_sound_raw
      io.write true
      io.write raw
    else
      io.write false
    end
    if raw = disable_sound_raw
      io.write true
      io.write raw
    else
      io.write false
    end
  end
end

# PotionDurationScale - Float
class Rosegold::DataComponents::PotionDurationScale < Rosegold::DataComponent
  property scale : Float32

  def initialize(@scale = 1.0_f32); end

  def self.read(io) : self
    new(io.read_float)
  end

  def write(io) : Nil
    io.write scale
  end
end

# SuspiciousStewEffects - array of {MobEffect id (VarInt via holderRegistry, no inline), VarInt duration}.
# MobEffect.STREAM_CODEC uses ByteBufCodecs.holderRegistry which has no inline branch — id 0 is a
# valid registry index (minecraft:speed), so there is NO id==0-means-inline escape.
class Rosegold::DataComponents::SuspiciousStewEffects < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times do
      io.read_var_int # mob effect registry id
      io.read_var_int # duration
    end
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# WritableBookContent
class Rosegold::DataComponents::WritableBookContent < Rosegold::DataComponent
  record Page, raw : String, filtered : String?

  property pages : Array(Page)

  def initialize(@pages : Array(Page) = [] of Page); end

  def self.read(io) : self
    count = io.read_var_int
    pages = Array(Page).new(count)
    count.times do
      raw = io.read_var_string
      has_filtered = io.read_bool
      filtered = has_filtered ? io.read_var_string : nil
      pages << Page.new(raw, filtered)
    end
    new(pages)
  end

  def write(io) : Nil
    io.write pages.size
    pages.each do |page|
      io.write page.raw
      io.write !page.filtered.nil?
      if filtered = page.filtered
        io.write filtered
      end
    end
  end
end

# WrittenBookContent
class Rosegold::DataComponents::WrittenBookContent < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_var_string # title raw
    has_filtered_title = capture.read_bool
    capture.read_var_string if has_filtered_title
    capture.read_var_string # author
    capture.read_var_int    # generation
    page_count = capture.read_var_int
    page_count.times do
      capture.read_nbt_unamed # page text component
      has_filtered = capture.read_bool
      capture.read_nbt_unamed if has_filtered
    end
    capture.read_bool # resolved
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# Instrument - ID or inline
class Rosegold::DataComponents::Instrument < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    has_holder = capture.read_bool
    if has_holder
      holder_type = capture.read_var_int
      if holder_type == 0
        # Inline instrument data
        sound_type = capture.read_var_int
        if sound_type == 0
          capture.read_var_string # sound name
          has_fixed_range = capture.read_bool
          capture.read_float if has_fixed_range
        end
        capture.read_float      # use_duration
        capture.read_float      # range
        capture.read_nbt_unamed # description
      end
    else
      capture.read_var_string # resource key
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# ProvidesTrimMaterial - EitherHolder<TrimMaterial>.
# Wire: bool first; true → Holder<TrimMaterial>, false → ResourceKey<TrimMaterial> (Identifier).
# Holder = VarInt id; if id == 0 ⇒ inline TrimMaterial follows; else ⇒ registry index (id - 1).
class Rosegold::DataComponents::ProvidesTrimMaterial < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    first = capture.read_bool
    if first
      holder_id = capture.read_var_int
      if holder_id == 0
        # Inline TrimMaterial: AssetInfo suffix + map<ResourceKey, String suffix> + description
        capture.read_var_string # base suffix
        override_count = capture.read_var_int
        override_count.times do
          capture.read_var_string # override key
          capture.read_var_string # suffix
        end
        capture.read_nbt_unamed # description TextComponent
      end
    else
      capture.read_var_string # resource key
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# OminousBottleAmplifier - VarInt
class Rosegold::DataComponents::OminousBottleAmplifier < Rosegold::DataComponent
  property amplifier : UInt32

  def initialize(@amplifier = 0_u32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write amplifier
  end
end

# JukeboxPlayable - ID or inline
class Rosegold::DataComponents::JukeboxPlayable < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    has_holder = capture.read_bool
    if has_holder
      holder_type = capture.read_var_int
      if holder_type == 0
        # Inline jukebox song data
        sound_type = capture.read_var_int
        if sound_type == 0
          capture.read_var_string # sound name
          has_fixed_range = capture.read_bool
          capture.read_float if has_fixed_range
        end
        capture.read_nbt_unamed # description
        capture.read_float      # duration
        capture.read_var_int    # output
      end
    else
      capture.read_var_string # resource key
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# ProvidesBannerPatterns - Identifier
class Rosegold::DataComponents::ProvidesBannerPatterns < Rosegold::DataComponent
  property pattern : String

  def initialize(@pattern = ""); end

  def self.read(io) : self
    new(io.read_var_string)
  end

  def write(io) : Nil
    io.write pattern
  end
end

# Recipes - list of Identifiers
class Rosegold::DataComponents::Recipes < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times { io.read_var_string }
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# LodestoneTracker
class Rosegold::DataComponents::LodestoneTracker < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    has_global_pos = capture.read_bool
    if has_global_pos
      capture.read_var_string # dimension
      capture.read_long       # position (packed)
    end
    capture.read_bool # tracked
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# FireworkExplosion
class Rosegold::DataComponents::FireworkExplosion < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_var_int # shape
    color_count = capture.read_var_int
    color_count.times { capture.read_int } # colors
    fade_count = capture.read_var_int
    fade_count.times { capture.read_int } # fade colors
    capture.read_bool                     # has_trail
    capture.read_bool                     # has_twinkle
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# Fireworks
class Rosegold::DataComponents::Fireworks < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_var_int # flight duration
    explosion_count = capture.read_var_int
    explosion_count.times do
      capture.read_var_int # shape
      color_count = capture.read_var_int
      color_count.times { capture.read_int }
      fade_count = capture.read_var_int
      fade_count.times { capture.read_int }
      capture.read_bool # has_trail
      capture.read_bool # has_twinkle
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# Profile - player head profile. Wire format differs between protocols:
#   772 (1.21.8): ResolvableProfile = {Optional<String> name, Optional<UUID> id, PropertyMap}
#   774+ (1.21.11+): Either<GameProfile, Partial> + PlayerSkin.Patch — captured via raw_bytes.
class Rosegold::DataComponents::Profile < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    if Client.protocol_version >= 774_u32
      read_774(capture)
    else
      read_772(capture)
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  # 772: Optional<String> name, Optional<UUID> id, PropertyMap properties
  private def self.read_772(io)
    has_name = io.read_bool
    io.read_var_string if has_name
    has_uuid = io.read_bool
    io.read_uuid if has_uuid
    read_property_map(io)
  end

  # 774: Either<GameProfile, Partial> discriminator bool + PlayerSkin.Patch
  #   Left (true):  GameProfile = UUID(16) + String name + PropertyMap
  #   Right (false): Partial = Optional<String> name + Optional<UUID> id + PropertyMap
  # Then PlayerSkin.Patch = 4 Optionals: body, cape, elytra (ResourceTexture=Identifier string), model (Bool)
  private def self.read_774(io)
    left = io.read_bool
    if left
      io.read_uuid
      io.read_var_string # name
      read_property_map(io)
    else
      has_name = io.read_bool
      io.read_var_string if has_name
      has_uuid = io.read_bool
      io.read_uuid if has_uuid
      read_property_map(io)
    end
    # PlayerSkin.Patch: body, cape, elytra (each Optional<Identifier>), model (Optional<Bool>)
    3.times do
      present = io.read_bool
      io.read_var_string if present
    end
    has_model = io.read_bool
    io.read_bool if has_model
  end

  private def self.read_property_map(io)
    prop_count = io.read_var_int
    prop_count.times do
      io.read_var_string # name
      io.read_var_string # value
      has_sig = io.read_bool
      io.read_var_string if has_sig
    end
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# NoteBlockSound - Identifier
class Rosegold::DataComponents::NoteBlockSound < Rosegold::DataComponent
  property sound : String

  def initialize(@sound = ""); end

  def self.read(io) : self
    new(io.read_var_string)
  end

  def write(io) : Nil
    io.write sound
  end
end

# BaseColor - VarInt (dye color)
class Rosegold::DataComponents::BaseColor < Rosegold::DataComponent
  property color : UInt32

  def initialize(@color = 0_u32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write color
  end
end

# PotDecorations - prefixed array of VarInts
class Rosegold::DataComponents::PotDecorations < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times { io.read_var_int }
    new
  end

  def write(io) : Nil
    io.write 4_u32
    4.times { io.write 0_u32 }
  end
end

# Container - list of Slots
class Rosegold::DataComponents::Container < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times { Rosegold::Slot.read(io) }
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# BlockState - map of property name -> value
class Rosegold::DataComponents::BlockState < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times do
      io.read_var_string # property name
      io.read_var_string # property value
    end
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# Bees - list of occupants. Per-entry entity_data layout differs between protocols:
#   772 (1.21.8): CustomData (bare CompoundTag: tag_type + body)
#   774+ (1.21.11+): TypedEntityData (VarInt entity_type + CompoundTag)
class Rosegold::DataComponents::Bees < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times do
      if Client.protocol_version >= 774_u32
        io.read_var_int    # entity_type
        io.read_nbt_unamed # entity data CompoundTag
      else
        io.read_nbt_unamed # CustomData: bare CompoundTag
      end
      io.read_var_int # ticks_in_hive
      io.read_var_int # min_ticks_in_hive
    end
    new
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# Lock - NBT compound
class Rosegold::DataComponents::Lock < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_nbt_unamed
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# ContainerLoot - loot table + seed
class Rosegold::DataComponents::ContainerLoot < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    capture.read_var_string # loot table
    capture.read_long       # seed
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# BreakSound - sound event ID or inline
class Rosegold::DataComponents::BreakSound < Rosegold::DataComponent
  property raw_bytes : Bytes = Bytes.empty

  def initialize; end

  def self.read(io) : self
    capture = Minecraft::IO::CaptureIO.new(io)
    sound_type = capture.read_var_int
    if sound_type == 0
      capture.read_var_string # sound id
      has_range = capture.read_bool
      capture.read_float if has_range
    end
    instance = new
    instance.raw_bytes = capture.buffer.to_slice.dup
    instance
  end

  def write(io) : Nil
    io.write(raw_bytes)
  end
end

# BlockPredicates - used by can_place_on, can_break.
# Per BlockPredicate.STREAM_CODEC (1.21.8/1.21.11):
#   Optional<HolderSet<Block>> blocks
#   Optional<StatePropertiesPredicate> properties
#   Optional<NbtPredicate> nbt
#   DataComponentMatchers components  (exact + partial predicate maps)
#
# DataComponentMatchers is effectively recursive Slot-component parsing. We read
# the common empty-map case correctly; any non-empty matchers raise and the
# packet-layer rescue falls back to RawPacket.
class Rosegold::DataComponents::BlockPredicates < Rosegold::DataComponent
  def initialize; end

  def self.read(io) : self
    count = io.read_var_int
    count.times do
      has_blocks = io.read_bool
      if has_blocks
        holder_type = io.read_var_int
        if holder_type == 0
          io.read_var_string # tag
        else
          (holder_type - 1).times { io.read_var_int }
        end
      end
      has_properties = io.read_bool
      if has_properties
        prop_count = io.read_var_int
        prop_count.times do
          io.read_var_string # property name
          is_exact = io.read_bool
          if is_exact
            io.read_var_string # exact value
          else
            io.read_var_string # min
            io.read_var_string # max
          end
        end
      end
      has_nbt = io.read_bool
      io.read_nbt_unamed if has_nbt
      read_data_component_matchers(io)
    end
    new
  end

  private def self.read_data_component_matchers(io)
    exact_count = io.read_var_int
    exact_count.times do
      component_type_id = io.read_var_int
      # Each exact entry = (VarInt component_type, value with that type's streamCodec).
      DataComponent.create_component(component_type_id, io)
    end
    partial_count = io.read_var_int
    if partial_count != 0
      raise Minecraft::NBT::DecodeError.new(
        "DataComponentMatchers with non-empty partial-predicate map " \
        "(count=#{partial_count}) is not supported; cannot advance IO stream safely"
      )
    end
  end

  def write(io) : Nil
    io.write 0_u32
  end
end

# CustomModelData - four prefixed arrays: floats, booleans, strings, colors (Int).
class Rosegold::DataComponents::CustomModelData < Rosegold::DataComponent
  property floats : Array(Float32)
  property booleans : Array(Bool)
  property strings : Array(String)
  property colors : Array(Int32)

  def initialize(@floats = [] of Float32, @booleans = [] of Bool,
                 @strings = [] of String, @colors = [] of Int32); end

  def self.read(io) : self
    float_count = io.read_var_int
    floats = Array(Float32).new(float_count) { io.read_float }
    bool_count = io.read_var_int
    booleans = Array(Bool).new(bool_count) { io.read_bool }
    string_count = io.read_var_int
    strings = Array(String).new(string_count) { io.read_var_string }
    color_count = io.read_var_int
    colors = Array(Int32).new(color_count) { io.read_int }
    new(floats, booleans, strings, colors)
  end

  def write(io) : Nil
    io.write floats.size
    floats.each { |float| io.write float }
    io.write booleans.size
    booleans.each { |bool| io.write bool }
    io.write strings.size
    strings.each { |string| io.write string }
    io.write colors.size
    colors.each { |color| io.write_full color }
  end
end

# Generic VarInt component (entity variants, enum types)
class Rosegold::DataComponents::VarIntComponent < Rosegold::DataComponent
  property value : UInt32

  def initialize(@value : UInt32 = 0_u32); end

  def self.read(io) : self
    new(io.read_var_int)
  end

  def write(io) : Nil
    io.write value
  end
end

# Generic Float component
class Rosegold::DataComponents::FloatComponent < Rosegold::DataComponent
  property value : Float32

  def initialize(@value : Float32 = 0.0_f32); end

  def self.read(io) : self
    new(io.read_float)
  end

  def write(io) : Nil
    io.write value
  end
end

# Holder component (registry entry holder: VarInt where 0 = inline with string, >0 = registry ID + 1)
class Rosegold::DataComponents::HolderComponent < Rosegold::DataComponent
  property value : UInt32
  property inline_identifier : String?

  def initialize(@value : UInt32 = 0_u32, @inline_identifier : String? = nil); end

  def self.read(io) : self
    holder_type = io.read_var_int
    inline = holder_type == 0 ? io.read_var_string : nil
    new(holder_type, inline)
  end

  def write(io) : Nil
    io.write value
    if value == 0
      io.write(inline_identifier || "")
    end
  end
end

# UseEffects (1.21.11) - 2 bools + 1 float
class Rosegold::DataComponents::UseEffects < Rosegold::DataComponent
  property? can_sprint : Bool
  property? interact_vibrations : Bool
  property speed_multiplier : Float32

  def initialize(@can_sprint = false, @interact_vibrations = false, @speed_multiplier = 1.0_f32); end

  def self.read(io) : self
    new(io.read_bool, io.read_bool, io.read_float)
  end

  def write(io) : Nil
    io.write @can_sprint
    io.write @interact_vibrations
    io.write speed_multiplier
  end
end

# AttackRange (1.21.11) - 6 floats
class Rosegold::DataComponents::AttackRange < Rosegold::DataComponent
  property min_range : Float32
  property max_range : Float32
  property min_creative_range : Float32
  property max_creative_range : Float32
  property hitbox_margin : Float32
  property mob_factor : Float32

  def initialize(@min_range = 0_f32, @max_range = 0_f32, @min_creative_range = 0_f32,
                 @max_creative_range = 0_f32, @hitbox_margin = 0_f32, @mob_factor = 0_f32); end

  def self.read(io) : self
    new(io.read_float, io.read_float, io.read_float, io.read_float, io.read_float, io.read_float)
  end

  def write(io) : Nil
    io.write min_range
    io.write max_range
    io.write min_creative_range
    io.write max_creative_range
    io.write hitbox_margin
    io.write mob_factor
  end
end

# SwingAnimation (1.21.11) - VarInt type + VarInt duration
class Rosegold::DataComponents::SwingAnimation < Rosegold::DataComponent
  property type_id : UInt32
  property duration : UInt32

  def initialize(@type_id = 0_u32, @duration = 0_u32); end

  def self.read(io) : self
    new(io.read_var_int, io.read_var_int)
  end

  def write(io) : Nil
    io.write type_id
    io.write duration
  end
end

# EitherHolder (1.21.11) - boolean discriminator + either VarInt (registry) or Identifier (resource key)
class Rosegold::DataComponents::EitherHolderComponent < Rosegold::DataComponent
  property? is_holder : Bool
  property holder_id : UInt32
  property resource_key : String?

  def initialize(@is_holder = true, @holder_id = 0_u32, @resource_key = nil); end

  def self.read(io) : self
    is_holder = io.read_bool
    if is_holder
      new(true, io.read_var_int)
    else
      new(false, 0_u32, io.read_var_string)
    end
  end

  def write(io) : Nil
    io.write is_holder?
    if is_holder?
      io.write holder_id
    else
      io.write(resource_key || "")
    end
  end
end

# Helper to read an optional Holder<SoundEvent> (bool present + holder format)
module Rosegold::DataComponents::SoundEventHelper
  def self.skip_optional_sound_event(io)
    present = io.read_bool
    return unless present
    skip_sound_event_holder(io)
  end

  def self.skip_sound_event_holder(io)
    id = io.read_var_int
    if id == 0
      # Inline: Identifier + optional Float
      io.read_var_string # sound location
      has_range = io.read_bool
      io.read_float if has_range # fixed range
    end
    # id > 0: registry lookup, no more data
  end
end

# PiercingWeapon (1.21.11) - 2 bools + 2 optional SoundEvent holders
class Rosegold::DataComponents::PiercingWeapon < Rosegold::DataComponent
  property? deals_knockback : Bool
  property? dismounts : Bool

  def initialize(@deals_knockback = false, @dismounts = false); end

  def self.read(io) : self
    deals_knockback = io.read_bool
    dismounts = io.read_bool
    SoundEventHelper.skip_optional_sound_event(io) # sound
    SoundEventHelper.skip_optional_sound_event(io) # hit_sound
    new(deals_knockback, dismounts)
  end

  def write(io) : Nil
    io.write @deals_knockback
    io.write @dismounts
    io.write false # no sound
    io.write false # no hit_sound
  end
end

# KineticWeapon (1.21.11) - complex: 2 VarInts + 3 optional conditions + 2 floats + 2 optional sounds
class Rosegold::DataComponents::KineticWeapon < Rosegold::DataComponent
  property contact_cooldown_ticks : UInt32
  property delay_ticks : UInt32
  property forward_movement : Float32
  property damage_multiplier : Float32

  def initialize(@contact_cooldown_ticks = 0_u32, @delay_ticks = 0_u32,
                 @forward_movement = 0_f32, @damage_multiplier = 0_f32); end

  private def self.skip_optional_condition(io)
    present = io.read_bool
    return unless present
    io.read_var_int # max_duration_ticks
    io.read_float   # min_speed
    io.read_float   # min_relative_speed
  end

  def self.read(io) : self
    contact_cooldown_ticks = io.read_var_int
    delay_ticks = io.read_var_int
    skip_optional_condition(io) # dismount_conditions
    skip_optional_condition(io) # knockback_conditions
    skip_optional_condition(io) # damage_conditions
    forward_movement = io.read_float
    damage_multiplier = io.read_float
    SoundEventHelper.skip_optional_sound_event(io) # sound
    SoundEventHelper.skip_optional_sound_event(io) # hit_sound
    new(contact_cooldown_ticks, delay_ticks, forward_movement, damage_multiplier)
  end

  def write(io) : Nil
    io.write contact_cooldown_ticks
    io.write delay_ticks
    io.write false # no dismount_conditions
    io.write false # no knockback_conditions
    io.write false # no damage_conditions
    io.write forward_movement
    io.write damage_multiplier
    io.write false # no sound
    io.write false # no hit_sound
  end
end

# TypedEntityData (1.21.11) - VarInt type ID + CompoundTag
class Rosegold::DataComponents::TypedEntityData < Rosegold::DataComponent
  property type_id : UInt32
  property data : Minecraft::NBT::Tag

  def initialize(@type_id = 0_u32, @data = Minecraft::NBT::CompoundTag.new); end

  def self.read(io) : self
    type_id = io.read_var_int
    nbt_data = io.read_nbt_unamed
    new(type_id, nbt_data)
  end

  def write(io) : Nil
    io.write type_id
    io.write data
  end
end

class Rosegold::Slot
  class_property enchantment_registry : Array(String) = [] of String
  class_property max_repair_cost : Int32 = 31

  property count : UInt32
  property components_to_add : Hash(String, DataComponent) # Component name -> structured component
  property components_to_remove : Set(String)              # Component names to remove

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

  def initialize(@count = 0_u32, @item_id_int = 0_u32, @components_to_add = Hash(String, DataComponent).new, @components_to_remove = Set(String).new); end

  def self.read(io) : Rosegold::Slot
    count = io.read_var_int
    return new(count) if count == 0 # Empty slot

    item_id_int = io.read_var_int

    # Read components to add
    components_to_add_count = io.read_var_int
    components_to_remove_count = io.read_var_int
    components_to_add = Hash(String, DataComponent).new

    components_to_add_count.times do |_|
      component_type = io.read_var_int
      name = DataComponentTypes.name_for(component_type, Client.protocol_version) || "unknown_#{component_type}"
      begin
        structured_component = DataComponent.create_component(component_type, io)
      rescue ex : Minecraft::NBT::DecodeError | UnknownComponentError
        Log.warn { "Dropping component #{name} (id=#{component_type}, proto=#{Client.protocol_version}): #{ex.message}" }
        raise ex
      end
      components_to_add[name] = structured_component
    end

    # Read components to remove
    components_to_remove = Set(String).new
    components_to_remove_count.times do
      component_type = io.read_var_int
      name = DataComponentTypes.name_for(component_type, Client.protocol_version) || "unknown_#{component_type}"
      components_to_remove.add(name)
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

    components_to_add.each do |name, component|
      component_id = DataComponentTypes.id_for(name, Client.protocol_version)
      raise "Unknown component name: #{name}" unless component_id
      io.write component_id
      component.write(io)
    end

    # Write components to remove
    components_to_remove.each do |name|
      component_id = DataComponentTypes.id_for(name, Client.protocol_version)
      raise "Unknown component name: #{name}" unless component_id
      io.write component_id
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
    @cached_item ||= MCData.default.items.find { |item| item.id == item_id_int } ||
                     raise "Unknown item ID: #{item_id_int}"
  end

  def damage
    damage_component = components_to_add["damage"]?
    return 0 unless damage_component.is_a?(DataComponents::Damage)
    damage_component.value.to_i32
  end

  def durability
    max_durability - damage
  end

  def max_durability
    max_damage_component = components_to_add["max_damage"]?
    if max_damage_component.is_a?(DataComponents::MaxDamage)
      max_damage_component.value.to_u16
    else
      item.max_durability || 0_u16
    end
  end

  def max_stack_size
    max_stack_component = components_to_add["max_stack_size"]?
    if max_stack_component.is_a?(DataComponents::MaxStackSize)
      max_stack_component.value.to_u8
    else
      item.stack_size
    end
  end

  def efficiency
    enchantments["efficiency"]? || 0
  end

  def tool_component : DataComponents::Tool?
    component = components_to_add["tool"]?
    component.is_a?(DataComponents::Tool) ? component : nil
  end

  # Get the mining speed from the tool component for a given block tag
  def tool_speed_for_tag(tag : String) : Float32?
    tool = tool_component
    return nil unless tool
    tool.rules.each do |rule|
      if rule.blocks_tag == tag || rule.blocks_tag == "minecraft:#{tag}"
        return rule.speed if rule.has_speed?
      end
    end
    nil
  end

  def enchantments
    enchant_component = components_to_add["enchantments"]?
    return Hash(String, Int8 | Int16 | Int32 | Int64 | UInt8).new unless enchant_component.is_a?(DataComponents::Enchantments)

    result = Hash(String, Int8 | Int16 | Int32 | Int64 | UInt8).new
    enchant_component.enchantments.each do |type_id, level|
      registry = Rosegold::Slot.enchantment_registry
      enchant_name = if !registry.empty? && type_id < registry.size
                       registry[type_id]
                     else
                       enchantment = MCData.default.enchantments.find { |e| e.id == type_id }
                       enchantment ? enchantment.name : "enchant_#{type_id}"
                     end
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

    enchanted? && repair_cost <= Slot.max_repair_cost
  end

  def repair_cost : Int32
    repair_component = components_to_add["repair_cost"]?
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

  def matches?(spec : Rosegold::Slot -> _)
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
  property? has_item : Bool
  property item_id_int : UInt32
  property count : UInt32
  property components_to_add : Hash(String, UInt32) # Component name -> CRC32 hash
  property components_to_remove : Set(String)       # Component names to remove

  def initialize(@has_item = false, @item_id_int = 0_u32, @count = 0_u32, @components_to_add = Hash(String, UInt32).new, @components_to_remove = Set(String).new); end

  def self.from_slot(slot : Slot) : HashedSlot
    if slot.empty?
      new(false)
    else
      # Generate CRC32 hashes for components
      hashed_components = Hash(String, UInt32).new
      slot.components_to_add.each do |name, component|
        component_id = DataComponentTypes.id_for(name, Client.protocol_version)
        raise "Unknown component name: #{name}" unless component_id
        component_buffer = Minecraft::IO::Memory.new
        component_buffer.write component_id
        component.write(component_buffer)
        component_data = component_buffer.to_slice
        crc32_hash = CRC32C.checksum(component_data)
        hashed_components[name] = crc32_hash
      end

      new(true, slot.item_id_int, slot.count, hashed_components, slot.components_to_remove)
    end
  end

  def self.from_window_slot(window_slot : WindowSlot) : HashedSlot
    from_slot(window_slot.as(Slot))
  end

  def write(io)
    # Hashed Item format: boolean presence flag (different from regular Slot which uses count-first)
    io.write has_item?
    return unless has_item?

    io.write item_id_int
    io.write count

    # Prefixed Array: components to add (count + entries)
    io.write components_to_add.size.to_u32
    components_to_add.each do |name, hash|
      component_id = DataComponentTypes.id_for(name, Client.protocol_version)
      raise "Unknown component name: #{name}" unless component_id
      io.write component_id
      io.write_full hash.to_i32! # CRC32C hash as Int (4 bytes, signed, big-endian)
    end

    # Prefixed Array: components to remove (count + entries)
    io.write components_to_remove.size.to_u32
    components_to_remove.each do |name|
      component_id = DataComponentTypes.id_for(name, Client.protocol_version)
      raise "Unknown component name: #{name}" unless component_id
      io.write component_id
    end
  end

  def empty?
    !has_item?
  end

  def present?
    has_item?
  end
end
