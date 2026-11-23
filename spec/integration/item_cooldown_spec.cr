require "../spec_helper"

class ItemCooldownClient < Rosegold::Client
  private alias HandUse = Rosegold::Serverbound::PlayerBlockPlacement | Rosegold::Serverbound::UseItem

  getter use_hands = [] of Rosegold::Hand
  property watched_target : Rosegold::Vec3i?
  getter block_use_trace = [] of {HandUse, Rosegold::Hand, UInt16?, UInt32}

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    use_hands << packet.hand if packet.is_a?(Rosegold::Serverbound::UseItem)
    if (target = watched_target) && (packet.is_a?(Rosegold::Serverbound::PlayerBlockPlacement) || packet.is_a?(Rosegold::Serverbound::UseItem))
      inventory = @observed_inventory ||= Rosegold::Inventory.new(self)
      block_use_trace << {packet, packet.hand, dimension.interaction_block_state(target), inventory.main_hand.count}
    end
    super
  end
end

Spectator.describe "Rosegold::Bot item cooldowns" do
  GROUP    = "rosegold:use_spec"
  COOLDOWN = %([use_cooldown={seconds:15.0,cooldown_group:"#{GROUP}"}])

  def wait_until(bot : Rosegold::Bot, ticks = 40, &)
    ticks.times do
      return true if yield
      break unless bot.connected? && bot.wait_tick
    end
    yield
  end

  def observed_client
    ItemCooldownClient.new(MC_TEST_HOST, MC_TEST_PORT, offline: {
      uuid:     "00000000-0000-0000-0000-000000000000",
      username: AdminBot::TEST_PLAYER,
    })
  end

  def watch_use_flags(client : Rosegold::Client)
    use_flags = [] of UInt8
    client.on(Rosegold::Clientbound::SetEntityData) do |packet|
      if packet.entity_id == client.player.entity_id && (flags = packet.values[8_u8]?).is_a?(UInt8)
        use_flags << ((flags & 1_u8) == 0 ? 0_u8 : flags & 3_u8)
      end
    end
    use_flags
  end

  it "sends the cooling main-hand use before raising the off-hand shield" do
    observed = observed_client
    observed.join_game do |client|
      bot = Rosegold::Bot.new(client)
      begin
        admin.tp 90.5, -60, 85.5
        admin.clear
        cooldowns = [] of Rosegold::Clientbound::SetCooldown
        client.on(Rosegold::Clientbound::SetCooldown) { |packet| cooldowns << packet }
        admin.chat "/item replace entity #{AdminBot::TEST_PLAYER} weapon.mainhand with minecraft:snowball#{COOLDOWN}"
        expect(wait_until(bot) {
          bot.main_hand.name == "snowball" && (bot.location - Rosegold::Vec3d.new(90.5, -60, 85.5)).length < 1.0
        }).to be_true
        bot.look &.up

        bot.use_hand hand: :main_hand
        expect(wait_until(bot) { cooldowns.any? { |packet| packet.group == GROUP && packet.duration > 0 } }).to be_true

        admin.chat "/item replace entity #{AdminBot::TEST_PLAYER} weapon.mainhand with minecraft:apple#{COOLDOWN}"
        admin.item_replace "weapon.offhand", "shield"
        expect(wait_until(bot) { bot.main_hand.name == "apple" && bot.inventory.off_hand.name == "shield" &&
          bot.main_hand.components_to_add["use_cooldown"]?.as?(Rosegold::DataComponents::UseCooldown).try(&.cooldown_group) == GROUP }).to be_true

        use_flags = watch_use_flags(client)
        observed.use_hands.clear
        bot.start_using_hand

        expect(wait_until(bot) { use_flags.includes?(3_u8) }).to be_true
        expect(observed.use_hands).to eq([Rosegold::Hand::MainHand, Rosegold::Hand::OffHand])
        expect(use_flags.includes?(1_u8)).to be_false
        expect(bot.main_hand.name).to eq("apple")
      ensure
        bot.stop_using_hand
        admin.clear
        cleaned = wait_until(bot) { bot.main_hand.empty? && bot.inventory.off_hand.empty? }
        expect(cleaned).to_eventually be_true, "Expected empty hands before disconnecting"
      end
    end
  end

  it "passes a cooling block item on an inert block before raising the off-hand shield" do
    observed = observed_client
    observed.join_game do |client|
      bot = Rosegold::Bot.new(client)
      position = Rosegold::Vec3d.new(84.5, -60, 91.5)
      support = Rosegold::Vec3i.new(84, -60, 89)
      target = support.up
      names = Rosegold::MCData.default.block_state_names
      group = "#{GROUP}_block"
      cooldown = %([use_cooldown={seconds:15.0,cooldown_group:"#{group}"}])
      prepared = false
      begin
        admin.chat "/gamemode survival #{AdminBot::TEST_PLAYER}"
        admin.tp position.x, position.y, position.z
        ready = wait_until(bot) do
          bot.gamemode == 0_i8 && !client.player.creative_mode? &&
            (bot.location - position).length < 0.05 && bot.world.block_state(support)
        end
        raise "Block cooldown fixture did not load" unless ready

        prepared = true
        admin.fill 83, -60, 88, 85, -57, 92, "air"
        admin.setblock support.x, support.y, support.z, "obsidian"
        admin.clear
        cooling = false
        client.on(Rosegold::Clientbound::SetCooldown) do |packet|
          cooling = packet.duration > 0 if packet.group == group
        end
        admin.item_replace "weapon.mainhand", "snowball#{cooldown}"
        raise "Snowball did not synchronize" unless wait_until(bot) { bot.main_hand.name == "snowball" }
        bot.look &.up
        bot.use_hand hand: :main_hand
        raise "Server did not confirm the shared cooldown" unless wait_until(bot) { cooling }

        admin.item_replace "weapon.mainhand", "stone#{cooldown}", 2
        admin.item_replace "weapon.offhand", "shield"
        ready = wait_until(bot) do
          main = bot.main_hand
          off = bot.inventory.off_hand
          component = main.components_to_add["use_cooldown"]?.as?(Rosegold::DataComponents::UseCooldown)
          main.name == "stone" && main.count == 2 && component.try(&.cooldown_group) == group &&
            off.name == "shield" && off.components_to_add.empty? && off.components_to_remove.empty? &&
            (bot.location - position).length < 0.05 && !bot.riding? && !client.player.sneaking? &&
            bot.world.block_state(support).try { |state| names[state] } == "obsidian" &&
            bot.world.block_state(target).try { |state| names[state] } == "air"
        end
        raise "Block cooldown fixture did not synchronize" unless ready

        support_state = bot.world.block_state(support)
        air = bot.world.block_state(target)
        bot.look_at target.centered_floor
        raise "Shared cooldown expired before the block use" unless cooling
        use_flags = watch_use_flags(client)
        ack = 0
        client.on(Rosegold::Clientbound::AcknowledgeBlockChange) { |packet| ack = packet.sequence }
        observed.watched_target = target
        bot.start_using_hand

        confirmed = wait_until(bot) do
          last_use = observed.block_use_trace.last?.try(&.[0])
          use_flags.includes?(3_u8) && last_use.is_a?(Rosegold::Serverbound::UseItem) && ack >= last_use.sequence
        end
        expect(confirmed).to be_true
        trace = observed.block_use_trace
        place = Rosegold::Serverbound::PlayerBlockPlacement
        use = Rosegold::Serverbound::UseItem
        main_hand = Rosegold::Hand::MainHand
        off_hand = Rosegold::Hand::OffHand
        route = trace.map do |packet, hand, _, _|
          aim = packet.as?(Rosegold::Serverbound::PlayerBlockPlacement).try { |placement| {placement.location, placement.face} }
          {packet.class, hand, aim}
        end
        expect(route).to eq([
          {place, main_hand, {support, BlockFace::Top}}, {use, main_hand, nil},
          {place, off_hand, {support, BlockFace::Top}}, {use, off_hand, nil},
        ])
        expect(trace.map { |_, _, state, count| {state, count} }).to eq([{air, 2_u32}] * 4)
        expect(use_flags.includes?(1_u8)).to be_false
        expect({bot.main_hand.name, bot.main_hand.count}).to eq({"stone", 2_u32})
        expect({bot.world.block_state(support), bot.world.block_state(target)}).to eq({support_state, air})
      ensure
        bot.stop_using_hand
        bot.wait_tick if bot.connected?
        if bot.connected?
          admin.clear
          admin.fill 83, -60, 88, 85, -57, 92, "air" if prepared
          cleaned = wait_until(bot) do
            bot.main_hand.empty? && bot.inventory.off_hand.empty? &&
              (!prepared || {support, target}.all? { |pos| bot.world.block_state(pos).try { |state| names[state] } == "air" })
          end
          expect(cleaned).to_eventually be_true, "Expected empty hands and cleared fixture before disconnecting"
        end
      end
    end
  end
end
