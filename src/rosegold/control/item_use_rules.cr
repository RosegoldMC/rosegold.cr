require "./block_use_rules"

# Default-class item behavior, checked against the decompiled Item, ShieldItem,
# BlockItem, Consumable and Player sources of every supported version. Names are
# listed only where the registration is a bare Item or BlockItem (or food with
# Foods.* that is not always edible) in every version that has the item.
module Rosegold::ItemUseRules
  alias Result = BlockUseRules::Result

  struct Decision
    getter result : Result
    getter? starts_sustained_use : Bool

    def initialize(@result, @starts_sustained_use = false); end
  end

  PLAIN_ITEMS = Set(String).new(%w(
    amethyst_shard angler_pottery_sherd archer_pottery_sherd armadillo_scute
    arms_up_pottery_sherd blade_pottery_sherd blaze_powder blaze_rod bone book bowl breeze_rod
    brewer_pottery_sherd brick burn_pottery_sherd charcoal clay_ball clock coal copper_ingot
    copper_nugget copper_pickaxe copper_sword danger_pottery_sherd diamond diamond_pickaxe
    diamond_sword echo_shard emerald explorer_pottery_sherd feather fermented_spider_eye
    firework_star flint flow_pottery_sherd friend_pottery_sherd ghast_tear
    glistering_melon_slice glowstone_dust gold_ingot gold_nugget golden_pickaxe golden_sword
    gunpowder guster_pottery_sherd heart_of_the_sea heart_pottery_sherd
    heartbreak_pottery_sherd howl_pottery_sherd iron_ingot iron_nugget iron_pickaxe iron_sword
    lapis_lazuli leather magma_cream miner_pottery_sherd mourner_pottery_sherd nautilus_shell
    nether_brick netherite_ingot netherite_pickaxe netherite_scrap netherite_sword
    ominous_trial_key paper phantom_membrane plenty_pottery_sherd popped_chorus_fruit
    prismarine_crystals prismarine_shard prize_pottery_sherd quartz rabbit_foot rabbit_hide
    raw_copper raw_gold raw_iron recovery_compass resin_brick scrape_pottery_sherd
    sheaf_pottery_sherd shelter_pottery_sherd shulker_shell skull_pottery_sherd slime_ball
    snort_pottery_sherd stick stone_pickaxe stone_sword sugar trial_key turtle_scute wheat
    wooden_pickaxe wooden_sword
  ))

  # Registered with food that is not always edible and a sustained consumable.
  HUNGER_FOODS = Set(String).new(%w(
    apple baked_potato beef beetroot beetroot_soup bread cod cooked_beef cooked_chicken
    cooked_cod cooked_mutton cooked_porkchop cooked_rabbit cooked_salmon cookie golden_carrot
    melon_slice mushroom_stew mutton porkchop pumpkin_pie rabbit rabbit_stew salmon
    tropical_fish
  ))

  # Registered as a plain BlockItem; Item#use is not overridden, but BlockItem#useOn is.
  BLOCK_ITEMS = Set(String).new(%w(
    stone granite diorite andesite deepslate cobblestone mossy_cobblestone dirt coarse_dirt
    grass_block podzol mycelium sand red_sand gravel netherrack sandstone clay obsidian
    crying_obsidian smooth_stone stone_bricks bricks end_stone blackstone terracotta
    iron_block gold_block diamond_block oak_planks spruce_planks birch_planks jungle_planks
    acacia_planks dark_oak_planks cherry_planks mangrove_planks bamboo_planks crimson_planks
    warped_planks pale_oak_planks
  ))

  # Components that cannot change Item#use or the default Item#useOn.
  NEUTRAL_COMPONENTS = Set(String).new(%w(
    custom_name item_name lore damage repair_cost custom_data enchantments
    enchantment_glint_override rarity unbreakable custom_model_data item_model tooltip_style
  ))

  # Plain items whose own useOn is the default PASS. Block items are excluded
  # because BlockItem#useOn places blocks.
  def self.default_use_on_passes?(name : String, held : Slot) : Bool
    return false unless unpatched?(held)
    PLAIN_ITEMS.includes?(name) || HUNGER_FOODS.includes?(name) || name == "shield" || name == "name_tag"
  end

  def self.evaluate(player : Player, held : Slot) : Decision
    unknown = Decision.new(Result::Unknown)
    return unknown unless {0, 1, 2}.includes?(player.gamemode)
    return Decision.new(Result::Pass) if held.empty?
    return unknown unless name = item_name(held)

    food = HUNGER_FOODS.includes?(name)
    name_tag = name == "name_tag"
    shield = name == "shield"
    return unknown unless food || shield || name_tag || PLAIN_ITEMS.includes?(name) || BLOCK_ITEMS.includes?(name)

    consumable = food
    sustained_consumption = true
    has_food = food
    always_eat = false
    blocks = shield
    held.components_to_remove.each do |key|
      case key
      when "food"           then has_food = false
      when "consumable"     then consumable = false
      when "blocks_attacks" then blocks = false
      else
        return unknown unless NEUTRAL_COMPONENTS.includes?(key)
      end
    end
    held.components_to_add.each do |key, component|
      case key
      when "food"
        return unknown unless component.is_a?(DataComponents::Food)
        has_food = true
        always_eat = component.can_always_eat?
      when "consumable"
        return unknown unless component.is_a?(DataComponents::Consumable)
        consumable = true
        sustained_consumption = component.consume_seconds * 20_f32 >= 1_f32
      else
        return unknown unless NEUTRAL_COMPONENTS.includes?(key)
      end
    end

    if consumable
      return Decision.new(Result::Fail) if has_food && !(player.invulnerable? || always_eat || player.food < 20)
      Decision.new(Result::Consume, sustained_consumption)
    elsif blocks
      Decision.new(Result::Consume, true)
    else
      Decision.new(Result::Pass)
    end
  end

  private def self.unpatched?(held : Slot) : Bool
    held.components_to_add.empty? && held.components_to_remove.empty?
  end

  private def self.item_name(held : Slot) : String?
    item = MCData.default.items.bsearch { |candidate| candidate.id >= held.item_id_int }
    item.name if item && item.id == held.item_id_int && item.name != "air"
  end
end
