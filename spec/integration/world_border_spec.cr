require "../spec_helper"

class WorldBorderUseClient < Rosegold::Client
  getter block_uses = [] of Rosegold::Serverbound::PlayerBlockPlacement
  getter other_uses = [] of Rosegold::Serverbound::Packet

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    case packet
    when Rosegold::Serverbound::PlayerBlockPlacement
      block_uses << packet
    when Rosegold::Serverbound::UseItem
      other_uses << packet
    end
    super
  end
end

module WorldBorderFixture
  STANDING      = Rosegold::Vec3d.new(120.5, -60, 118.5)
  OUTSIDE       = Rosegold::Vec3i.new(122, -59, 118)
  INSIDE        = Rosegold::Vec3i.new(118, -59, 118)
  OUTSIDE_PLACE = Rosegold::Vec3i.new(121, -59, 118)
  INSIDE_PLACE  = Rosegold::Vec3i.new(119, -59, 118)
  TEST_SIZE     =        244
  DEFAULT_SIZE  = 59_999_968

  def self.observed_client
    WorldBorderUseClient.new(MC_TEST_HOST, MC_TEST_PORT, offline: {
      uuid:     "00000000-0000-0000-0000-000000000000",
      username: AdminBot::TEST_PLAYER,
    })
  end

  def self.clear_blocks : Bool
    return false unless admin.fill(117, -60, 117, 123, -57, 119, "air")
    2.times { return false unless admin.wait_tick }
    true
  rescue
    false
  end

  def self.clear_hands(bot : Rosegold::Bot) : Bool
    admin.clear && wait_until(bot) { bot.main_hand.empty? && bot.inventory.off_hand.empty? }
  rescue
    false
  end

  def self.restore_border : Bool
    return false unless admin.wait_tick

    admin_bot = admin.bot
    size = admin_bot.client.wait_for(Rosegold::Clientbound::SetBorderSize, timeout: 5.seconds) do
      raise "Could not send the border restoration command" unless admin_bot.chat "/worldborder set #{DEFAULT_SIZE}"
    end
    size.size == DEFAULT_SIZE
  rescue
    false
  end

  def self.move_admin(admin_bot : Rosegold::Bot, position : Rosegold::Vec3d) : Bool
    admin_bot.chat("/tp @s #{position.x} #{position.y} #{position.z}") &&
      wait_until(admin_bot) { (admin_bot.location - position).length < 0.1 }
  end

  def self.restore_admin(world : String, position : Rosegold::Vec3d) : Bool
    return false unless admin.wait_tick

    admin_bot = admin.bot
    admin_bot.world.name == world && move_admin(admin_bot, position)
  rescue
    false
  end

  def self.block_name(client : Rosegold::Client, position : Rosegold::Vec3i) : String?
    client.dimension_for_test.block_state(position).try { |state| Rosegold::Block.from_block_state_id(state).id_str }
  end

  def self.wait_until(bot : Rosegold::Bot, ticks = 40, &)
    ticks.times do
      return true if yield
      return false unless bot.connected? && bot.wait_tick
    end
    yield
  end

  def self.aim(bot : Rosegold::Bot, support : Rosegold::Vec3i)
    bot.look_at support.to_f64 + Rosegold::Vec3d.new(0.5, 0.5, 0.5)
  end
end

Spectator.describe "Rosegold::Bot world border block use" do
  it "does not send a block use against support outside the border but still uses in-bounds support" do
    observed = WorldBorderFixture.observed_client
    initial_border = nil.as(Rosegold::Clientbound::InitializeBorder?)
    observed.on(Rosegold::Clientbound::InitializeBorder) { |packet| initial_border = packet }
    size_changed = false
    blocks_changed = false
    original_admin_location = nil.as(Tuple(String, Rosegold::Vec3d)?)
    restored = false
    blocks_cleared = false
    hands_cleared = false
    admin_restored = true

    observed.join_game do |client|
      bot = Rosegold::Bot.new(client)
      begin
        WorldBorderFixture.wait_until(bot) { !initial_border.nil? }
        border = initial_border
        default_size = WorldBorderFixture::DEFAULT_SIZE
        unless border && border.center_x.zero? && border.center_z.zero? && border.old_size == default_size && border.new_size == default_size
          raise "Expected a default world border before the block-use spec"
        end

        admin.tp WorldBorderFixture::STANDING.x, WorldBorderFixture::STANDING.y, WorldBorderFixture::STANDING.z
        expect(WorldBorderFixture.wait_until(bot, 60) { (bot.location - WorldBorderFixture::STANDING).length < 1.0 }).to be_true
        blocks_changed = true
        raise "Could not clear the block-use fixture" unless WorldBorderFixture.clear_blocks
        admin.clear

        outside = WorldBorderFixture::OUTSIDE
        inside = WorldBorderFixture::INSIDE
        admin.setblock outside.x, outside.y, outside.z, "stone"
        admin.setblock inside.x, inside.y, inside.z, "stone"
        admin.item_replace "weapon.mainhand", "cobblestone"
        admin.item_replace "weapon.offhand", "cobblestone"
        expect(WorldBorderFixture.wait_until(bot) {
          WorldBorderFixture.block_name(client, outside) == "stone" &&
            WorldBorderFixture.block_name(client, inside) == "stone" &&
            bot.inventory.off_hand.name == "cobblestone" && bot.main_hand.name == "cobblestone"
        }).to be_true

        raise "Admin did not tick before resizing the border" unless admin.wait_tick
        admin_bot = admin.bot
        raise "Admin must be in the test world" unless admin_bot.world.name == bot.world.name

        original_admin_location = {admin_bot.world.name, admin_bot.location}
        safe_position = Rosegold::Vec3d.new(106.5, -60, 105.5)
        raise "Could not position the synthetic admin" unless WorldBorderFixture.move_admin(admin_bot, safe_position)

        admin_location = admin_bot.location
        safe_limit = WorldBorderFixture::TEST_SIZE / 2 - 1
        unless admin_bot.world.name == bot.world.name && admin_location.x.abs < safe_limit && admin_location.z.abs < safe_limit
          raise "Admin must be safely inside the temporary border"
        end

        size_changed = true
        size = client.wait_for(Rosegold::Clientbound::SetBorderSize, timeout: 5.seconds) do
          raise "Could not send the resize command" unless admin_bot.chat "/worldborder set #{WorldBorderFixture::TEST_SIZE}"
        end
        expect(size.size).to eq(WorldBorderFixture::TEST_SIZE.to_f64)
        bot.wait_ticks 2

        WorldBorderFixture.aim(bot, outside)
        observed.block_uses.clear
        observed.other_uses.clear
        bot.use_hand
        bot.wait_ticks 8
        expect(observed.block_uses).to be_empty
        expect(observed.other_uses).to be_empty
        expect(WorldBorderFixture.block_name(client, WorldBorderFixture::OUTSIDE_PLACE)).to eq("air")
        expect(WorldBorderFixture.block_name(client, outside)).to eq("stone")

        WorldBorderFixture.aim(bot, inside)
        bot.use_hand
        expect(WorldBorderFixture.wait_until(bot) {
          WorldBorderFixture.block_name(client, WorldBorderFixture::INSIDE_PLACE) == "cobblestone"
        }).to be_true
        expect(observed.block_uses.map(&.location)).to eq([inside])
        expect(observed.block_uses.map(&.hand)).to eq([Rosegold::Hand::MainHand])
      ensure
        hands_cleared = WorldBorderFixture.clear_hands(bot)
        restored = !size_changed || WorldBorderFixture.restore_border
        blocks_cleared = !blocks_changed || WorldBorderFixture.clear_blocks
        if restored && (original = original_admin_location)
          admin_restored = WorldBorderFixture.restore_admin(*original)
        end
      end
    end

    raise "world border was not restored" unless restored
    raise "world border fixture blocks were not cleared" unless blocks_cleared
    raise "world border fixture hands were not cleared" unless hands_cleared
    raise "world border fixture admin position was not restored" unless admin_restored
  ensure
    observed.try &.connection?.try &.disconnect("End of world border spec")
  end
end
