require "../spec_helper"

class DiggingSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
  end

  def interactions_for_test
    interactions
  end

  def self.server_protocol
    result = Channel(UInt32 | Exception).new(1)
    spawn do
      begin
        result.send Rosegold::Client.status(MC_TEST_HOST, MC_TEST_PORT.to_u16).json_response["version"]["protocol"].as_i.to_u32
      rescue ex
        result.send ex
      end
    end

    select
    when value = result.receive
      case value
      when Socket::ConnectError
        Rosegold::Client::LATEST_PROTOCOL
      when Exception
        raise value
      else
        value
      end
    when timeout(5.seconds)
      raise "Timed out detecting the digging spec server protocol"
    end
  end
end

# Capture the CI server version before other specs reset the shared protocol.
# Keep these unit specs runnable without a server.
DIGGING_TEST_PROTOCOL = DiggingSpecClient.server_protocol

Spectator.describe "Digging vegetation" do
  let(bot_client) { DiggingSpecClient.new("localhost") }
  let(interactions) { bot_client.interactions_for_test }
  let(target) { Rosegold::Vec3i.new(0, 0, 2) }

  def set_block(location, name, half = nil)
    block = Rosegold::MCData.default.blocks.find! { |entry| entry.id_str == name }
    state = if half
              (block.min_state_id..block.max_state_id).find! { |id| Rosegold::MCData.default.block_state_names[id].includes?("half=#{half}") }
            else
              block.min_state_id
            end
    bot_client.dimension_for_test.set_block_state(location, state)
  end

  def aim(x = 0.5, y = 0.9)
    bot_client.player.feet = Rosegold::Vec3d.new(x, y - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    bot_client.player.look = Rosegold::Look.new(0_f32, 0_f32)
  end

  def starts
    bot_client.sent_packets.select(Rosegold::Serverbound::PlayerAction).select(&.status.start?)
  end

  before_each do
    Rosegold::Client.protocol_version = DIGGING_TEST_PROTOCOL
    dimension = bot_client.dimension_for_test
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
    set_block(target, "firefly_bush")
    aim
  end

  after_each do
    Rosegold::Client.reset_protocol_version!
  end

  it "digs through the upper part of the vanilla outline" do
    interactions.start_digging
    interactions.tick

    expect(starts.map(&.location)).to eq([target])
  end

  it "digs through the edge of the vanilla outline" do
    aim(0.05, 0.5)
    interactions.start_digging
    interactions.tick

    expect(starts.map(&.location)).to eq([target])
  end

  it "keeps a solid foreground block in front of the bush" do
    foreground = Rosegold::Vec3i.new(0, 0, 1)
    set_block(foreground, "stone")
    interactions.start_digging
    interactions.tick

    expect(starts.map(&.location)).to eq([foreground])
  end

  it "does not extend the outline outside the block" do
    aim(1.05, 0.5)
    interactions.start_digging
    interactions.tick

    expect(starts).to be_empty
  end

  it "does not dig a bush beyond survival reach" do
    set_block(target, "air")
    set_block(Rosegold::Vec3i.new(0, 0, 6), "firefly_bush")
    interactions.start_digging
    interactions.tick

    expect(starts).to be_empty
  end

  it "reaches the bush after server updates remove foreground vegetation" do
    aim(0.5, 0.5)
    foreground = Rosegold::Vec3i.new(0, 0, 1)
    set_block(foreground, "bush")
    interactions.start_digging
    interactions.tick
    Rosegold::Clientbound::BlockChange.new(foreground, 0_u16).callback(bot_client)
    2.times { interactions.tick }

    expect(starts.map(&.location)).to eq([foreground, target])
  end

  it "does not restart a held dig when start_digging is repeated" do
    set_block(target, "stone")
    interactions.tick
    interactions.start_digging
    interactions.tick
    progress = interactions.block_damage_progress
    interactions.start_digging
    interactions.tick

    expect(starts.size).to eq(1)
    expect(interactions.block_damage_progress).to be > progress
  end

  it "digs through the small fern's upper strip" do
    set_block(target, "fern")
    aim(0.5, 0.78)
    interactions.start_digging
    interactions.tick

    expect(starts.map(&.location)).to eq([target])
  end

  it "misses above the small fern's outline" do
    set_block(target, "fern")
    aim(0.5, 0.83)
    interactions.start_digging
    interactions.tick

    expect(starts).to be_empty
  end

  it "keeps the small fern's outline inset from the block edge" do
    set_block(target, "fern")
    aim(0.05, 0.5)
    interactions.start_digging
    interactions.tick

    expect(starts).to be_empty
  end

  it "digs through the top of either large fern half" do
    {"upper", "lower"}.each do |half|
      set_block(target, "large_fern", half)
      interactions.start_digging
      interactions.tick
      interactions.stop_digging
    end

    expect(starts.map(&.location)).to eq([target, target])
  end

  it "digs through the outer edge of either large fern half" do
    aim(0.05, 0.5)
    {"upper", "lower"}.each do |half|
      set_block(target, "large_fern", half)
      interactions.start_digging
      interactions.tick
      interactions.stop_digging
    end

    expect(starts.map(&.location)).to eq([target, target])
  end

  it "does not extend either large fern half outside the block" do
    aim(1.05, 0.5)
    {"upper", "lower"}.each do |half|
      set_block(target, "large_fern", half)
      interactions.start_digging
      interactions.tick
      interactions.stop_digging
    end

    expect(starts).to be_empty
  end

  it "keeps a solid block in front of the small fern's upper strip" do
    set_block(target, "fern")
    aim(0.5, 0.78)
    foreground = Rosegold::Vec3i.new(0, 0, 1)
    set_block(foreground, "stone")
    interactions.start_digging
    interactions.tick

    expect(starts.map(&.location)).to eq([foreground])
  end

  it "does not dig a fern beyond survival reach" do
    set_block(target, "air")
    set_block(Rosegold::Vec3i.new(0, 0, 6), "fern")
    aim(0.5, 0.78)
    interactions.start_digging
    interactions.tick

    expect(starts).to be_empty
  end

  it "continues held digging from a small fern to a large fern" do
    foreground = Rosegold::Vec3i.new(0, 0, 1)
    set_block(foreground, "fern")
    set_block(target, "large_fern", "lower")
    aim(0.5, 0.78)
    interactions.start_digging
    interactions.tick
    Rosegold::Clientbound::BlockChange.new(foreground, 0_u16).callback(bot_client)
    interactions.start_digging
    2.times { interactions.tick }

    expect(starts.map(&.location)).to eq([foreground, target])
  end
end
