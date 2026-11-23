require "../spec_helper"

private module MultipartPlacementFixture
  SUPPORT = Rosegold::Vec3i.new(100, -56, 100)
  BASE    = SUPPORT + Rosegold::Vec3i.new(0, 1, 0)
  UPPER   = BASE + Rosegold::Vec3i.new(0, 1, 0)
  NORTH   = BASE + Rosegold::Vec3i.new(0, 0, -1)
  SOUTH   = BASE + Rosegold::Vec3i.new(0, 0, 1)
  CELLS   = {BASE, UPPER, NORTH, SOUTH}

  def self.states(bot : Rosegold::Bot)
    CELLS.map do |pos|
      bot.world.block_state(pos).try { |state| Rosegold::MCData.default.block_state_names[state] }
    end
  end

  def self.wait_until(client : Rosegold::Client, &)
    60.times do
      return true if yield
      break unless client.wait_tick
    end
    yield
  end

  def self.clear
    admin.fill 96, -56, 96, 104, -53, 104, "air"
  end
end

private class MultipartPlacementClient < Rosegold::Client
  getter placements = [] of Rosegold::Serverbound::PlayerBlockPlacement
  getter placement_states = [] of Tuple(UInt16?, UInt16?, UInt16?, UInt16?)

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    if packet.is_a?(Rosegold::Serverbound::PlayerBlockPlacement)
      placement_states << MultipartPlacementFixture::CELLS.map { |pos| dimension.interaction_block_state(pos) }
      super
      placements << packet
    else
      super
    end
  end
end

Spectator.describe "Rosegold::Bot multipart block placement" do
  def attempt_placement(item : String, approach : Int32, *, blocked : Rosegold::Vec3i? = nil, &)
    client = MultipartPlacementClient.new(MC_TEST_HOST, MC_TEST_PORT, offline: {
      uuid:     "00000000-0000-0000-0000-000000000000",
      username: AdminBot::TEST_PLAYER,
    })
    client.join_game
    bot = Rosegold::Bot.new(client)
    fixture = MultipartPlacementFixture

    position = MultipartPlacementFixture::BASE.centered_3d + Rosegold::Vec3d.new(-0.25, -0.5, 2 * approach)
    admin.tp position.x, position.y, position.z
    raise "Multipart fixture was not loaded" unless fixture.wait_until(client) { bot.world.block_state(MultipartPlacementFixture::SUPPORT) }

    fixture.clear
    admin.fill 96, -56, 96, 104, -56, 104, "stone"
    if blocked
      admin.setblock blocked.x, blocked.y, blocked.z, "obsidian"
    end
    admin.tp position.x, position.y, position.z
    admin.item_replace "weapon.mainhand", item
    initial = MultipartPlacementFixture::CELLS.map { |pos| pos == blocked ? "obsidian" : "air" }
    ready = fixture.wait_until(client) do
      (bot.location - position).length < 0.05 && bot.main_hand.name == item &&
        bot.world.block_state(MultipartPlacementFixture::SUPPORT).try { |state| Rosegold::MCData.default.block_state_names[state] } == "stone" &&
        fixture.states(bot) == initial
    end
    raise "Multipart fixture did not synchronize" unless ready

    original_states = MultipartPlacementFixture::CELLS.map { |pos| bot.world.block_state(pos) }
    ack = nil.as(Int32?)
    client.on(Rosegold::Clientbound::AcknowledgeBlockChange) { |packet| ack = packet.sequence }

    if item == "oak_door"
      bot.use_hand(MultipartPlacementFixture::SUPPORT + BlockFace::Top - Rosegold::Vec3d.new(0.25, 0, 0), hand: :main_hand)
    else
      bot.place_block_against MultipartPlacementFixture::SUPPORT, :top
    end

    confirmed = fixture.wait_until(client) do
      if (placement = client.placements.first?) && (sequence = ack)
        sequence >= placement.sequence
      else
        false
      end
    end
    expect(confirmed).to be_true
    8.times do
      raise "Disconnected while checking placement retries" unless client.wait_tick
    end
    expect(client.placements.map { |packet| {packet.location, packet.face, packet.hand} }).to eq([
      {MultipartPlacementFixture::SUPPORT, BlockFace::Top, Rosegold::Hand::MainHand},
    ])
    expect(client.placement_states).to eq([original_states])
    yield fixture.states(bot)
  ensure
    begin
      if bot
        admin.item_replace "weapon.mainhand", "air"
        MultipartPlacementFixture.clear
        admin.wait_ticks 2
      end
    ensure
      client.try &.connection?.try &.disconnect("End of multipart placement spec")
    end
  end

  it "places both oak door halves with the server's north-facing left hinge" do
    attempt_placement("oak_door", 1) do |states|
      expect(states).to eq({
        "oak_door[facing=north, half=lower, hinge=left, open=false, powered=false]",
        "oak_door[facing=north, half=upper, hinge=left, open=false, powered=false]",
        "air", "air",
      })
    end
  end

  it "places both oak door halves with the server's south-facing right hinge" do
    attempt_placement("oak_door", -1) do |states|
      expect(states).to eq({
        "oak_door[facing=south, half=lower, hinge=right, open=false, powered=false]",
        "oak_door[facing=south, half=upper, hinge=right, open=false, powered=false]",
        "air", "air",
      })
    end
  end

  it "places a north-facing red bed with its head north of the foot" do
    attempt_placement("red_bed", 1) do |states|
      expect(states).to eq({
        "red_bed[facing=north, occupied=false, part=foot]", "air",
        "red_bed[facing=north, occupied=false, part=head]", "air",
      })
    end
  end

  it "places a south-facing red bed with its head south of the foot" do
    attempt_placement("red_bed", -1) do |states|
      expect(states).to eq({
        "red_bed[facing=south, occupied=false, part=foot]", "air", "air",
        "red_bed[facing=south, occupied=false, part=head]",
      })
    end
  end

  it "does not retry a door placement with a blocked upper half" do
    attempt_placement("oak_door", 1, blocked: MultipartPlacementFixture::UPPER) do |states|
      expect(states).to eq({"air", "obsidian", "air", "air"})
    end
  end

  it "does not retry a bed placement with a blocked head" do
    attempt_placement("red_bed", -1, blocked: MultipartPlacementFixture::SOUTH) do |states|
      expect(states).to eq({"air", "air", "air", "obsidian"})
    end
  end
end
