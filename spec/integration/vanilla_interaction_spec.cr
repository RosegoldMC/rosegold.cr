require "../spec_helper"

class Rosegold::Client
  def vanilla_interaction_state
    interactions
  end
end

class VanillaInteractionClient < Rosegold::Client
  getter entity_interactions = [] of Rosegold::Serverbound::InteractEntity
  getter use_hands = [] of Rosegold::Hand
  getter block_uses = [] of {Rosegold::Vec3i, Array(String?), Array(String?)}
  property watched_blocks = [] of Rosegold::Vec3i

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    unless watched_blocks.empty?
      case packet
      when Rosegold::Serverbound::PlayerBlockPlacement
        use_hands << packet.hand
        block_uses << {packet.location, confirmed_states, block_states(predicted: true)}
      when Rosegold::Serverbound::UseItem
        use_hands << packet.hand
      end
    end
    super
    entity_interactions << packet if packet.is_a?(Rosegold::Serverbound::InteractEntity)
  end

  def confirmed_states
    block_states(predicted: false)
  end

  private def block_states(*, predicted)
    world = dimension_for_test
    names = Rosegold::MCData.default.block_state_names
    watched_blocks.map do |position|
      state = predicted ? world.interaction_block_state(position) : world.block_state(position)
      state.try { |id| names[id] }
    end
  end
end

module VanillaInteractionFixture
  ORIGIN    = Rosegold::Vec3i.new(60, -60, 60)
  STONE     = Rosegold::Vec3i.new(60, -59, 58)
  LEVER     = Rosegold::Vec3i.new(60, -59, 59)
  LEVER_AIM = Rosegold::Vec3d.new(60.5, -58.5, 59.1)
  CART      = Rosegold::Vec3d.new(60.5, -59.9375, 62.5)

  def self.observed_client
    VanillaInteractionClient.new(MC_TEST_HOST, MC_TEST_PORT, offline: {
      uuid:     "00000000-0000-0000-0000-000000000000",
      username: AdminBot::TEST_PLAYER,
    })
  end

  def self.clear
    admin.chat "/kill @e[type=minecraft:cow,tag=rg_vanilla_use]"
    admin.chat "/kill @e[type=minecraft:minecart,tag=rg_vanilla_use]"
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

  def self.block_name(client : Rosegold::Client, position : Rosegold::Vec3i)
    client.dimension_for_test.block_state(position).try { |state| Rosegold::Block.from_block_state_id(state).id_str }
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

  def self.watch_use_flags(client : Rosegold::Client) : Array(UInt8)
    use_flags = [] of UInt8
    client.on Rosegold::Clientbound::SetEntityData do |packet|
      if packet.entity_id == client.player.entity_id && (flags = packet.values[8_u8]?).is_a?(UInt8)
        use_flags << ((flags & 1_u8) == 0 ? 0_u8 : flags & 3_u8)
      end
    end
    use_flags
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

  it "places with the off hand after a main-hand pass only when the hand is selected automatically" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        anchor = VanillaInteractionFixture::STONE
        target = VanillaInteractionFixture::LEVER
        admin.setblock target.x, target.y, target.z, "air"
        admin.item_replace "weapon.offhand", "cobblestone"
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          bot.main_hand.empty? && bot.inventory.off_hand.name == "cobblestone" &&
            VanillaInteractionFixture.block_name(client, anchor) == "stone" &&
            VanillaInteractionFixture.block_name(client, target) == "air"
        }).to be_true
        bot.look_at anchor.to_f64 + Rosegold::Vec3d.new(0.5, 0.5, 0.5)

        bot.use_hand hand: :main_hand
        bot.wait_ticks 8
        expect(VanillaInteractionFixture.block_name(client, target)).to eq("air")

        bot.use_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          VanillaInteractionFixture.block_name(client, target) == "cobblestone"
        }).to be_true
      end
    end
  end

  it "stops automatic hand selection when the main hand toggles a lever" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        admin.item_replace "weapon.offhand", "cobblestone"
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          bot.main_hand.empty? && bot.inventory.off_hand.name == "cobblestone"
        }).to be_true
        bot.look_at VanillaInteractionFixture::LEVER_AIM

        bot.use_hand
        expect(VanillaInteractionFixture.wait_until(bot) { VanillaInteractionFixture.powered?(client) == true }).to be_true
        bot.wait_ticks 8
        expect(VanillaInteractionFixture.powered?(client)).to eq(true)
        expect(bot.inventory.off_hand.name).to eq("cobblestone")
      end
    end
  end

  def expect_block_use(bot, observed_client, target, before, after)
    observed_client.block_uses.clear
    observed_client.use_hands.clear
    bot.use_hand

    expect(VanillaInteractionFixture.wait_until(bot, 40) {
      observed_client.confirmed_states == after
    }).to be_true
    expect(observed_client.block_uses).to eq([{target, before, after}])
    expect(observed_client.use_hands).to eq([Rosegold::Hand::MainHand])
  end

  it "predicts and confirms both halves when opening and closing doors without using the off hand" do
    observed_client = VanillaInteractionFixture.observed_client
    observed_client.join_game do |client|
      bot = Rosegold::Bot.new(client)
      expect(VanillaInteractionFixture.prepare(bot)).to be_true
      lower = VanillaInteractionFixture::ORIGIN.south(2)
      upper = lower.up
      observed_client.watched_blocks = [lower, upper]
      admin.item_replace "weapon.offhand", "cobblestone"
      expect(VanillaInteractionFixture.wait_until(bot, 40) {
        bot.main_hand.empty? && bot.inventory.off_hand.name == "cobblestone"
      }).to be_true

      {"oak_door", "waxed_copper_door"}.each do |door|
        closed = ["lower", "upper"].map { |half| "#{door}[facing=south, half=#{half}, hinge=left, open=false, powered=false]" }
        opened = closed.map &.sub("open=false", "open=true")
        admin.setblock lower.x, lower.y, lower.z, "air"
        admin.setblock lower.x, lower.y, lower.z, closed[0].delete(' ')
        admin.setblock upper.x, upper.y, upper.z, closed[1].delete(' ')
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          observed_client.confirmed_states == closed
        }).to be_true

        bot.look_at upper.to_f64.plus(0.5, 0.5, 0.1)
        expect_block_use(bot, observed_client, upper, closed, opened)
        bot.look_at lower.to_f64.plus(0.9375, 0.5, 0.5)
        expect_block_use(bot, observed_client, lower, opened, closed)
        expect(bot.inventory.off_hand.name).to eq("cobblestone")
      end
    end
  end

  it "predicts and confirms a gate turning to the player's facing when it opens" do
    observed_client = VanillaInteractionFixture.observed_client
    observed_client.join_game do |client|
      bot = Rosegold::Bot.new(client)
      expect(VanillaInteractionFixture.prepare(bot)).to be_true
      gate = VanillaInteractionFixture::ORIGIN.south(2)
      observed_client.watched_blocks = [gate]
      closed = ["oak_fence_gate[facing=north, in_wall=false, open=false, powered=false]"]
      opened = ["oak_fence_gate[facing=south, in_wall=false, open=true, powered=false]"]
      admin.setblock gate.x, gate.y, gate.z, closed[0].delete(' ')
      expect(VanillaInteractionFixture.wait_until(bot, 40) {
        observed_client.confirmed_states == closed
      }).to be_true

      bot.look_at gate.to_f64.plus(0.5, 0.5, 0.5)
      expect_block_use(bot, observed_client, gate, closed, opened)
      expect_block_use(bot, observed_client, gate, opened, [opened[0].sub("open=true", "open=false")])
    end
  end

  it "keeps the automatically selected off-hand shield active until released" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        admin.item_replace "weapon.offhand", "shield"
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          bot.main_hand.empty? && bot.inventory.off_hand.name == "shield"
        }).to be_true
        bot.look_at Rosegold::Vec3d.new(bot.x, bot.y + 5, bot.z)

        use_flags = VanillaInteractionFixture.watch_use_flags(client)
        bot.start_using_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { use_flags.includes?(3_u8) }).to be_true
        bot.wait_ticks 12
        expect(use_flags.all? { |flags| flags == 3_u8 }).to be_true

        bot.stop_using_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { use_flags.last? == 0_u8 }).to be_true
      end
    end
  end

  it "raises the off-hand shield when held use passes through a minecart while sneaking" do
    observed_client = VanillaInteractionFixture.observed_client
    observed_client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(VanillaInteractionFixture.prepare(bot)).to be_true
        position = VanillaInteractionFixture::CART
        admin.chat %(/summon minecraft:minecart #{position.x} #{position.y} #{position.z} {NoGravity:1b,Tags:["rg_vanilla_use"]})
        admin.item_replace "weapon.offhand", "shield"
        find_cart = -> {
          client.dimension_for_test.entities.values.find do |entity|
            entity.metadata.try(&.name) == "minecart" && (entity.position - position).length < 0.5
          end
        }
        bot.sneak
        expect(VanillaInteractionFixture.wait_until(bot, 40) {
          bot.sneaking? && bot.main_hand.empty? && bot.inventory.off_hand.name == "shield" && !find_cart.call.nil?
        }).to be_true
        cart = find_cart.call || raise "Minecart did not spawn"
        bot.wait_tick
        bot.look_at cart.position.up(0.3)

        use_flags = VanillaInteractionFixture.watch_use_flags(client)
        bot.start_using_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { use_flags.includes?(3_u8) }).to be_true
        expect(observed_client.entity_interactions.any? { |packet|
          packet.entity_id == cart.entity_id && packet.sneaking? && packet.hand == Rosegold::Hand::OffHand
        }).to be_true
        expect(bot.riding?).to be_false

        bot.stop_using_hand
        expect(VanillaInteractionFixture.wait_until(bot, 40) { use_flags.last? == 0_u8 }).to be_true
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
