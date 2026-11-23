require "../spec_helper"

class ItemCooldownClient < Rosegold::Client
  getter use_hands = [] of Rosegold::Hand

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    use_hands << packet.hand if packet.is_a?(Rosegold::Serverbound::UseItem)
    super
  end
end

Spectator.describe "Rosegold::Bot item cooldowns" do
  GROUP    = "rosegold:use_spec"
  COOLDOWN = %([use_cooldown={seconds:15.0,cooldown_group:"#{GROUP}"}])

  def wait_until(bot : Rosegold::Bot, ticks = 40, &)
    ticks.times do
      return true if yield
      bot.wait_tick
    end
    yield
  end

  it "sends the cooling main-hand use before raising the off-hand shield" do
    observed = ItemCooldownClient.new(MC_TEST_HOST, MC_TEST_PORT, offline: {
      uuid:     "00000000-0000-0000-0000-000000000000",
      username: AdminBot::TEST_PLAYER,
    })
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

        use_flags = [] of UInt8
        client.on(Rosegold::Clientbound::SetEntityData) do |packet|
          if packet.entity_id == client.player.entity_id && (flags = packet.values[8_u8]?).is_a?(UInt8)
            use_flags << ((flags & 1_u8) == 0 ? 0_u8 : flags & 3_u8)
          end
        end
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
end
