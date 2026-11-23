require "../spec_helper"
require "../../src/rosegold/control/item_use_rules"

Spectator.describe Rosegold::ItemUseRules do
  before_each { Rosegold::Client.protocol_version = Rosegold::Client::LATEST_PROTOCOL }
  after_each { Rosegold::Client.reset_protocol_version! }

  def mc
    Rosegold::MCData.default
  end

  let(player) { Rosegold::Player.new }

  def item(name : String)
    Rosegold::Slot.new(1_u32, mc.items.find! { |entry| entry.name == name }.id)
  end

  def evaluate(held)
    Rosegold::ItemUseRules.evaluate(player, held).result
  end

  it "passes an empty hand and plain items with no use behavior" do
    expect(evaluate(Rosegold::Slot.new)).to eq(Rosegold::BlockUseRules::Result::Pass)
    {"stick", "coal", "iron_sword", "iron_pickaxe", "book", "stone", "dirt", "grass_block", "oak_planks"}.each do |name|
      expect(evaluate(item(name))).to eq(Rosegold::BlockUseRules::Result::Pass)
    end
  end

  it "fails a hunger food only when full and not invulnerable, and consumes it otherwise" do
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      {"apple", "bread", "cooked_beef"}.each do |name|
        player.food = 20_u32
        expect(evaluate(item(name))).to eq(Rosegold::BlockUseRules::Result::Fail)
        player.food = 19_u32
        expect(evaluate(item(name))).to eq(Rosegold::BlockUseRules::Result::Consume)
        player.food = 20_u32
        player.invulnerable = true
        expect(evaluate(item(name))).to eq(Rosegold::BlockUseRules::Result::Consume)
        player.invulnerable = false
      end
    end
  end

  it "consumes a shield through its blocks_attacks component in every supported version" do
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      shield = item("shield")
      expect(evaluate(shield)).to eq(Rosegold::BlockUseRules::Result::Consume)
      expect(Rosegold::ItemUseRules.evaluate(player, shield).starts_sustained_use?).to be_true
    end
  end

  it "applies known food and consumable patches and keeps unresolved patches unknown" do
    player.food = 20_u32
    always = item("apple")
    always.components_to_add["food"] = Rosegold::DataComponents::Food.new(4_u32, 0.3_f32, true)
    expect(evaluate(always)).to eq(Rosegold::BlockUseRules::Result::Consume)

    never = item("golden_apple")
    expect(evaluate(never)).to eq(Rosegold::BlockUseRules::Result::Unknown)

    no_food = item("apple")
    no_food.components_to_remove << "food"
    expect(evaluate(no_food)).to eq(Rosegold::BlockUseRules::Result::Consume)

    no_consumable = item("apple")
    no_consumable.components_to_remove << "consumable"
    expect(evaluate(no_consumable)).to eq(Rosegold::BlockUseRules::Result::Pass)

    eating = item("stick")
    eating.components_to_add["food"] = Rosegold::DataComponents::Food.new(1_u32, 0.0_f32, false)
    eating.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new
    expect(evaluate(eating)).to eq(Rosegold::BlockUseRules::Result::Fail)
    player.food = 10_u32
    expect(evaluate(eating)).to eq(Rosegold::BlockUseRules::Result::Consume)

    renamed = item("stick")
    renamed.components_to_remove << "lore"
    expect(evaluate(renamed)).to eq(Rosegold::BlockUseRules::Result::Pass)

    custom = item("stick")
    custom.components_to_remove << "use_cooldown"
    expect(evaluate(custom)).to eq(Rosegold::BlockUseRules::Result::Unknown)

    stripped = item("shield")
    stripped.components_to_remove << "blocks_attacks"
    expect(evaluate(stripped)).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(Rosegold::ItemUseRules.evaluate(player, stripped).starts_sustained_use?).to be_false
    stripped.components_to_remove.delete("blocks_attacks")
    stripped.components_to_remove << "enchantments"
    expect(Rosegold::ItemUseRules.evaluate(player, stripped).starts_sustained_use?).to be_true
  end

  it "passes a name tag, including with a neutral custom_name patch" do
    tag = item("name_tag")
    expect(evaluate(tag)).to eq(Rosegold::BlockUseRules::Result::Pass)
    tag.components_to_remove << "custom_name"
    expect(evaluate(tag)).to eq(Rosegold::BlockUseRules::Result::Pass)
    tag.components_to_remove << "use_cooldown"
    expect(evaluate(tag)).to eq(Rosegold::BlockUseRules::Result::Unknown)
    expect(Rosegold::ItemUseRules.default_use_on_passes?("name_tag", item("name_tag"))).to be_true
  end

  it "does not guess items outside the proven default classes or restricted modes" do
    {"carrot", "golden_apple", "chorus_fruit", "bucket", "bow", "ender_pearl", "oak_log", "iron_axe", "air"}.each do |name|
      expect(evaluate(item(name))).to eq(Rosegold::BlockUseRules::Result::Unknown)
    end
    player.gamemode = 3_i8
    expect(evaluate(item("stick"))).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end
end
