require "../spec_helper"

class Rosegold::Client
  def vanilla_interaction_state
    interactions
  end
end

module VanillaInteractionFixture
  ORIGIN    = Rosegold::Vec3i.new(60, -60, 60)
  STONE     = Rosegold::Vec3i.new(60, -59, 58)
  LEVER     = Rosegold::Vec3i.new(60, -59, 59)
  LEVER_AIM = Rosegold::Vec3d.new(60.5, -58.5, 59.1)

  def self.clear
    admin.chat "/kill @e[type=minecraft:cow,tag=rg_vanilla_use]"
    admin.chat "/kill @e[type=minecraft:item,x=58,y=-60,z=56,dx=4,dy=4,dz=8]"
    admin.fill 58, -60, 56, 62, -56, 64, "air"
    admin.wait_ticks 2
  end

  def self.prepare(bot : Rosegold::Bot) : Bool
    return false if bot.riding?
    admin.tp 60.5, -60, 60.5
    return false unless wait_until(bot, 60) { (bot.location - Rosegold::Vec3d.new(60.5, -60, 60.5)).length < 1.0 }
    return false unless wait_until(bot, 60) { !bot.client.dimension_for_test.block_state(STONE.x, STONE.y, STONE.z).nil? }
    clear
    admin.chat "/clear rosegoldtest"
    admin.setblock STONE.x, STONE.y, STONE.z, "stone"
    admin.setblock LEVER.x, LEVER.y, LEVER.z, "lever[face=wall,facing=south,powered=false]"
    wait_until(bot, 40) { powered?(bot.client) == false }
  end

  def self.powered?(client : Rosegold::Client) : Bool?
    state = client.dimension_for_test.block_state(LEVER.x, LEVER.y, LEVER.z)
    return nil unless state
    name = Rosegold::MCData.default.block_state_names[state]
    return nil unless name.includes?("lever")
    name.includes?("powered=true")
  end

  def self.wait_until(bot : Rosegold::Bot, ticks = 20, &)
    ticks.times do
      return true if yield
      bot.wait_tick
    end
    yield
  end

  def self.settle(bot : Rosegold::Bot) : Bool
    wait_until(bot) { powered?(bot.client) == false }
  end
end

Spectator.describe "Rosegold::Bot vanilla interaction ordering" do
  around_each do |example|
    example.run
  ensure
    VanillaInteractionFixture.clear
  end

  it "drops a use tap queued with stop_digging while a dig is staged, then toggles a later tap" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        expect(client.player.creative_mode?).to be_false
        bot.look_at VanillaInteractionFixture::LEVER_AIM
        expect(VanillaInteractionFixture.settle(bot)).to be_true

        bot.start_digging
        expect(VanillaInteractionFixture.wait_until(bot, 10) { !client.vanilla_interaction_state.digging_block.nil? }).to be_true

        bot.stop_digging
        bot.use_hand
        bot.wait_ticks 8

        expect(client.vanilla_interaction_state.digging_block).to be_nil
        expect(VanillaInteractionFixture.powered?(client)).to eq(false)
        expect(client.dimension_for_test.block_state(VanillaInteractionFixture::LEVER.x, VanillaInteractionFixture::LEVER.y, VanillaInteractionFixture::LEVER.z)).to_not be_nil

        bot.use_hand
        expect(VanillaInteractionFixture.wait_until(bot) { VanillaInteractionFixture.powered?(client) == true }).to be_true
      end
    end
  end

  it "toggles when the tap follows the stopped dig by one tick" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        bot.look_at VanillaInteractionFixture::LEVER_AIM
        expect(VanillaInteractionFixture.settle(bot)).to be_true

        bot.start_digging
        expect(VanillaInteractionFixture.wait_until(bot, 10) { !client.vanilla_interaction_state.digging_block.nil? }).to be_true

        bot.stop_digging
        bot.wait_tick
        bot.use_hand
        expect(VanillaInteractionFixture.wait_until(bot) { VanillaInteractionFixture.powered?(client) == true }).to be_true
      end
    end
  end

  it "sends each close-spaced tap and does not leave use held" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        bot.look_at VanillaInteractionFixture::LEVER_AIM
        expect(VanillaInteractionFixture.settle(bot)).to be_true

        first = client.vanilla_interaction_state.last_hand_tap_sequence
        bot.use_hand
        bot.wait_tick
        after_first = client.vanilla_interaction_state.last_hand_tap_sequence
        bot.use_hand
        bot.wait_tick
        after_second = client.vanilla_interaction_state.last_hand_tap_sequence

        expect(after_first).to_not eq(first)
        expect(after_second).to_not eq(after_first)

        bot.wait_ticks 12
        expect(VanillaInteractionFixture.wait_until(bot) { VanillaInteractionFixture.powered?(client) == false }).to be_true
        bot.wait_ticks 12
        expect(VanillaInteractionFixture.powered?(client)).to eq(false)
      end
    end
  end

  it "uses an aimed cow with an empty bucket in the off hand" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        admin.chat "/summon minecraft:cow 60.5 -60 62.5 {NoAI:1b,Silent:1b,Invulnerable:1b,PersistenceRequired:1b,Tags:[\"rg_vanilla_use\"]}"
        admin.item_replace "weapon.offhand", "bucket"
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          client.dimension_for_test.entities.values.any? { |entity| entity.metadata.try(&.name) == "cow" }
        }).to be_true
        expect(VanillaInteractionFixture.wait_until(bot, 40) { bot.inventory.off_hand.name == "bucket" }).to be_true

        bot.look_at Rosegold::Vec3d.new(60.5, -59.3, 62.5)
        bot.use_hand hand: :off_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { bot.inventory.off_hand.name == "milk_bucket" }).to be_true
      end
    end
  end

  it "replaces an instantly broken wall torch with stone from the same tick's cached hit" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        position = VanillaInteractionFixture::LEVER
        admin.setblock position.x, position.y, position.z, "wall_torch[facing=south]"
        admin.give "stone"
        block_name = -> { client.dimension_for_test.block_state(position).try { |state| Rosegold::Block.from_block_state_id(state).id_str } }
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          block_name.call == "wall_torch" && bot.inventory.count("stone") > 0
        }).to be_true
        bot.inventory.pick! "stone"
        bot.look_at Rosegold::Vec3d.new(60.5, -58.55, 59.18)
        bot.attack
        bot.use_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { block_name.call == "stone" }).to be_true
      end
    end
  end
end
