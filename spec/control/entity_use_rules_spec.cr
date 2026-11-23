require "../spec_helper"
require "../../src/rosegold/control/entity_use_rules"

Spectator.describe Rosegold::EntityUseRules do
  alias Result = Rosegold::BlockUseRules::Result

  SOURCE_BACKED_PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32, 777_u32}

  after_each { Rosegold::Client.reset_protocol_version! }

  let(player) { Rosegold::Player.new }
  let(empty_hand) { Rosegold::Slot.new }

  def entity(name : String) : Rosegold::Entity
    type = Rosegold::Entity.metadata_for_protocol.find! { |data| data.name == name }
    Rosegold::Entity.new(42_u32, UUID.random, type.id.to_u32, Rosegold::Vec3d.new(1, 64, 2),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
  end

  def item(name : String) : Rosegold::Slot
    Rosegold::Slot.new(1_u32, Rosegold::MCData.default.items.find! { |entry| entry.name == name }.id)
  end

  def named_tag : Rosegold::Slot
    item("name_tag").tap { |slot| slot.components_to_add["custom_name"] = Rosegold::DataComponents::CustomName.new("Bob") }
  end

  def evaluate(target : Rosegold::Entity, held = empty_hand)
    Rosegold::EntityUseRules.evaluate(player, target, held)
  end

  def each_backed(&)
    SOURCE_BACKED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      yield
    end
  end

  it "passes for every entity in spectator mode on all enabled protocols" do
    player.gamemode = 3_i8
    SOURCE_BACKED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      {"player", "armor_stand", "minecart", "cow"}.each do |name|
        expect(evaluate(entity(name), item("name_tag"))).to eq(Result::Pass)
      end
    end
  end

  it "passes for another player with an empty hand or an inert unpatched item" do
    each_backed do
      expect(evaluate(entity("player"))).to eq(Result::Pass)
      {"stick", "apple", "bread", "shield", "stone"}.each do |name|
        expect(evaluate(entity("player"), item(name))).to eq(Result::Pass)
      end
    end
  end

  it "does not prove patched or unlisted items on another player" do
    each_backed do
      patched = item("stick").tap { |slot| slot.components_to_remove << "max_stack_size" }
      expect(evaluate(entity("player"), patched)).to eq(Result::Unknown)
      expect(evaluate(entity("player"), item("shears"))).to eq(Result::Unknown)
      expect(evaluate(entity("player"), item("saddle"))).to eq(Result::Unknown)
    end
  end

  it "consumes on a non-marker armor stand without a name tag" do
    each_backed do
      expect(evaluate(entity("armor_stand"))).to eq(Result::Consume)
      expect(evaluate(entity("armor_stand"), item("stick"))).to eq(Result::Consume)
    end
  end

  it "does not prove a marker armor stand" do
    each_backed do
      marker = entity("armor_stand")
      marker.tracked_data[15_u8] = 0x10_u8
      expect(evaluate(marker)).to eq(Result::Unknown)
    end
  end

  it "uses a named name tag on an armor stand and passes otherwise on a player" do
    each_backed do
      expect(evaluate(entity("armor_stand"), named_tag)).to eq(Result::Success)
      expect(evaluate(entity("armor_stand"), item("name_tag"))).to eq(Result::Pass)
      expect(evaluate(entity("player"), named_tag)).to eq(Result::Pass)
      extra = named_tag.tap { |slot| slot.components_to_add["lore"] = Rosegold::DataComponents::Lore.new }
      expect(evaluate(entity("armor_stand"), extra)).to eq(Result::Unknown)
    end
  end

  it "mounts a plain minecart unless sneaking or occupied, regardless of the held item" do
    each_backed do
      cart = entity("minecart")
      vacant = Rosegold::Client.protocol_version == 777_u32 ? Result::Consume : Result::Success
      expect(evaluate(cart)).to eq(vacant)
      expect(evaluate(cart, item("shears"))).to eq(vacant)

      player.sneaking = true
      expect(evaluate(cart)).to eq(Result::Pass)
      player.sneaking = false

      cart.passenger_ids << 7_u32
      expect(evaluate(cart)).to eq(Result::Pass)
    end
  end

  it "succeeds on a furnace minecart even when sneaking, except while holding fuel" do
    each_backed do
      cart = entity("furnace_minecart")
      player.sneaking = true
      expect(evaluate(cart)).to eq(Result::Success)
      expect(evaluate(cart, item("stick"))).to eq(Result::Success)
      expect(evaluate(cart, item("coal"))).to eq(Result::Unknown)
      player.sneaking = false
    end
  end

  it "leaves mobs and other entities unknown" do
    each_backed do
      {"cow", "chest_minecart", "oak_boat"}.each do |name|
        expect(evaluate(entity(name))).to eq(Result::Unknown)
      end
    end
  end

  it "leaves unresolvable held items unknown" do
    each_backed do
      expect(evaluate(entity("player"), Rosegold::Slot.new(1_u32, 999_999_u32))).to eq(Result::Unknown)
    end
  end
end
