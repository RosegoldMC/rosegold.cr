require "../spec_helper"

class Rosegold::Interactions
  def block_along_for_test(start : Vec3d, reach : Vec3d)
    reach_block_along(start, reach).try(&.block)
  end
end

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

Spectator.describe "Digging block outlines" do
  let(bot_client) { DiggingSpecClient.new("localhost") }
  let(interactions) { bot_client.interactions_for_test }
  let(target) { Rosegold::Vec3i.new(0, 0, 2) }

  def set_block(location, name, *properties)
    block = Rosegold::MCData.default.blocks.find! { |entry| entry.id_str == name }
    offset = block.states.reduce(0) do |index, property|
      index *= property.num_values
      if requested = properties.find(&.starts_with?("#{property.name}="))
        values = property.type.bool? ? {"true", "false"} : (property.values || raise "Missing values for #{property.name}")
        value = requested.split('=', 2).last
        index += values.index(value) || raise "Unknown property value #{requested}"
      end
      index
    end
    state = block.min_state_id + offset.to_u16
    bot_client.dimension_for_test.set_block_state(location, state)
    state
  end

  def aim(x = 0.5, y = 0.9, z = 0.5, look = Rosegold::Look::SOUTH)
    bot_client.player.feet = Rosegold::Vec3d.new(x, y - Rosegold::Player::DEFAULT_EYE_HEIGHT, z)
    bot_client.player.look = look
  end

  def starts
    bot_client.sent_packets.select(Rosegold::Serverbound::PlayerAction).select(&.status.start?)
  end

  def dig_at(x, y, z = 0.5, look = Rosegold::Look::SOUTH)
    interactions.stop_digging
    interactions.tick
    bot_client.sent_packets.clear
    aim(x, y, z, look)
    interactions.start_digging
    interactions.tick
    starts
  end

  def load_chunk(x, z)
    dimension = bot_client.dimension_for_test
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(x, z, Minecraft::IO::Memory.new(data.to_slice), dimension))
  end

  before_each do
    Rosegold::Client.protocol_version = DIGGING_TEST_PROTOCOL
    load_chunk(0, 0)
    set_block(target, "firefly_bush")
    aim
  end

  after_each do
    Rosegold::Client.reset_protocol_version!
  end

  sample [
    {"cave_vines", "berries=true", {0.9, 0.9}, {0.04, 0.9}},
    {"cave_vines_plant", "berries=false", {0.9, 0.9}, {0.04, 0.9}},
    {"small_dripleaf", "half=lower", {0.5, 0.8}, {0.5, 0.83}},
    {"small_dripleaf", "half=upper", {0.5, 0.8}, {0.5, 0.83}},
    {"wither_rose", "", {0.5, 0.5}, {0.5, 0.65}},
    {"open_eyeblossom", "", {0.5, 0.5}, {0.5, 0.65}},
    {"closed_eyeblossom", "", {0.5, 0.5}, {0.5, 0.65}},
    {"dandelion", "", {0.5, 0.5}, {0.5, 0.65}},
    {"poppy", "", {0.5, 0.5}, {0.5, 0.65}},
    {"sunflower", "half=lower", {0.5, 0.9}, {1.05, 0.9}},
    {"sunflower", "half=upper", {0.5, 0.9}, {1.05, 0.9}},
    {"weeping_vines", "", {0.5, 0.58}, {0.5, 0.54}},
    {"weeping_vines_plant", "", {0.9, 0.3}, {0.95, 0.3}},
    {"twisting_vines", "", {0.5, 0.92}, {0.5, 0.96}},
    {"twisting_vines_plant", "", {0.5, 0.98}, {0.2, 0.98}},
    {"cobweb", "", {0.05, 0.96}, {1.05, 0.96}},
    {"spore_blossom", "", {0.5, 0.83}, {0.5, 0.8}},
    {"brown_mushroom", "", {0.5, 0.35}, {0.5, 0.4}},
    {"torch", "", {0.5, 0.5}, {0.3, 0.5}},
    {"tripwire", "attached=true", {0.8, 0.08}, {0.8, 0.04}},
    {"tripwire", "attached=false", {0.8, 0.48}, {0.8, 0.52}},
  ] do |outline|
    it "hits inside the outline but misses just outside it" do
      name, property, hit, miss = outline
      set_block(target, name, property)

      expect(dig_at(*hit).map(&.location)).to eq([target])
      expect(dig_at(*miss)).to be_empty
    end
  end

  sample ["glow_lichen", "sculk_vein"] do |name|
    it "hits each attached face but sees through the gap between them" do
      set_block(target, name, "east=true", "west=true", "down=false", "north=false", "south=false", "up=false")
      behind = Rosegold::Vec3i.new(0, 0, 3)
      set_block(behind, "stone")

      expect(dig_at(0.04, 0.5).map(&.location)).to eq([target])
      expect(dig_at(0.96, 0.5).map(&.location)).to eq([target])
      expect(dig_at(0.5, 0.5).map(&.location)).to eq([behind])

      east_face = dig_at(0.5, 0.5, 2.5, Rosegold::Look::EAST).first
      expect(east_face.location).to eq(target)
      expect(east_face.face).to eq(BlockFace::West)
    end
  end

  it "targets the redstone wire's low dot and only the side that rises" do
    set_block(target, "redstone_wire", "east=up", "north=none", "south=none", "west=none")

    expect(dig_at(0.5, 0.05).map(&.location)).to eq([target])
    expect(dig_at(0.5, 0.08)).to be_empty
    expect(dig_at(0.97, 0.85).map(&.location)).to eq([target])
    expect(dig_at(0.03, 0.85)).to be_empty
  end

  sample [
    {"pink_petals", "flower_amount"},
    {"wildflowers", "flower_amount"},
    {"leaf_litter", "segment_amount"},
  ] do |cover|
    it "targets the occupied quarter of a one-segment ground cover" do
      name, amount = cover
      set_block(target, name, "#{amount}=1", "facing=north")

      expect(dig_at(0.25, 0.04).map(&.location)).to eq([target])
      expect(dig_at(0.75, 0.04)).to be_empty
      expect(dig_at(0.25, 1.5, 2.75, Rosegold::Look::SOUTH.down)).to be_empty
      expect(dig_at(0.25, 0.21)).to be_empty

      set_block(target, name, "#{amount}=4", "facing=north")
      expect(dig_at(0.75, 0.04).map(&.location)).to eq([target])
    end
  end

  it "picks flowers at their position-dependent offsets on either side of x=0" do
    load_chunk(-1, 0)
    set_block(target, "air")
    west_flower = Rosegold::Vec3i.new(-1, 0, 2)
    east_flower = Rosegold::Vec3i.new(0, 0, 4)
    set_block(west_flower, "poppy")
    set_block(east_flower, "poppy")

    expect(dig_at(-0.2, 0.45).map(&.location)).to eq([west_flower])
    expect(dig_at(-0.5, 0.45)).to be_empty
    expect(dig_at(0.15, 0.45).map(&.location)).to eq([east_flower])
    expect(dig_at(0.5, 0.45)).to be_empty
  end

  it "uses honey's full outline without expanding its inset movement collision" do
    state = set_block(target, "honey_block")
    collision = Rosegold::MCData.default.block_state_collision_shapes[state]

    expect(collision).not_to be_empty
    expect(collision.any?(&.contains?(Rosegold::Vec3f.new(0.03_f32, 0.97_f32, 0.5_f32)))).to be_false
    expect(dig_at(0.03, 0.97).map(&.location)).to eq([target])
  end

  it "targets the current cobweb when the bot's eyes are inside it" do
    set_block(target, "cobweb")
    set_block(Rosegold::Vec3i.new(0, 0, 3), "stone")

    hit = dig_at(0.5, 0.5, 2.5).first
    expect(hit.location).to eq(target)
    expect(hit.face).to eq(BlockFace::North)
  end

  it "targets a cobweb when the eyes are on its minimum X edge" do
    set_block(target, "cobweb")
    set_block(Rosegold::Vec3i.new(0, 0, 4), "stone")

    expect(dig_at(0.0, 0.5, 2.5).map(&.location)).to eq([target])
  end

  it "visits the Z neighbor before the X neighbor at an exact corner tie" do
    z_neighbor = Rosegold::Vec3i.new(0, 0, 1)
    set_block(z_neighbor, "stone")
    set_block(Rosegold::Vec3i.new(1, 0, 0), "stone")

    hit = interactions.block_along_for_test(Rosegold::Vec3d.new(0.5, 0.5, 0.5), Rosegold::Vec3d.new(3.0, 0.0, 3.0))
    expect(hit).to eq(z_neighbor)
  end

  it "marks a scaffolding placement from inside the outline while sneaking" do
    set_block(target, "scaffolding")
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == "scaffolding" }
    bot_client.inventory_menu[36] = Rosegold::Slot.new(1_u32, item.id)
    bot_client.player.sneaking = true
    bot_client.player.feet = Rosegold::Vec3d.new(0.5, 0.5 - Rosegold::Player::SNEAKING_EYE_HEIGHT, 2.5)

    interactions.tap_using_hand
    interactions.tick

    packet = bot_client.sent_packets.select(Rosegold::Serverbound::PlayerBlockPlacement).first
    expect(packet.location).to eq(target)
    expect(packet.inside_block?).to be_true
  end

  it "does not attack an out-of-reach entity or dig through it" do
    set_block(target, "air")
    stone = Rosegold::Vec3i.new(0, 0, 5)
    set_block(stone, "stone")
    zombie_type = Rosegold::Entity.metadata_for_protocol.find! { |entity| entity.name == "zombie" }
    zombie = Rosegold::Entity.new(1_u32, UUID.random, zombie_type.id.to_u32, Rosegold::Vec3d.new(0.5, 0.0, 4.35), 0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    entities = bot_client.dimension_for_test.entities
    entities[zombie.entity_id.to_u64] = zombie

    expect(dig_at(0.5, 0.5, 0.75)).to be_empty
    expect(bot_client.sent_packets.select(Rosegold::Serverbound::Attack)).to be_empty
    expect(bot_client.sent_packets.select(Rosegold::Serverbound::InteractEntity)).to be_empty

    entities.clear
    expect(dig_at(0.5, 0.5, 0.75).map(&.location)).to eq([stone])
  end

  it "does not target a thin outline beyond survival reach but does in creative" do
    set_block(target, "air")
    distant = Rosegold::Vec3i.new(0, 0, 5)
    set_block(distant, "glow_lichen", "north=true", "east=false", "west=false", "down=false", "south=false", "up=false")

    expect(dig_at(0.5, 0.5, 0.4)).to be_empty
    bot_client.player.gamemode = 1_i8
    expect(dig_at(0.5, 0.5, 0.4).map(&.location)).to eq([distant])
  end

  it "only targets a light block when the matching item is held in the main hand" do
    set_block(target, "light")
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == "light" }
    light = Rosegold::Slot.new(1_u32, item.id)

    expect(dig_at(0.5, 0.5)).to be_empty
    bot_client.inventory_menu[45] = light
    expect(dig_at(0.5, 0.5)).to be_empty
    bot_client.inventory_menu[36] = light
    expect(dig_at(0.5, 0.5).map(&.location)).to eq([target])
  end

  it "ignores an unknown held item when picking block outlines" do
    bot_client.inventory_menu[36] = Rosegold::Slot.new(1_u32, UInt32::MAX)
    interactions.tick

    set_block(target, "light")
    expect(dig_at(0.5, 0.5)).to be_empty
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
      set_block(target, "large_fern", "half=#{half}")
      interactions.start_digging
      interactions.tick
      interactions.stop_digging
    end

    expect(starts.map(&.location)).to eq([target, target])
  end

  it "digs through the outer edge of either large fern half" do
    aim(0.05, 0.5)
    {"upper", "lower"}.each do |half|
      set_block(target, "large_fern", "half=#{half}")
      interactions.start_digging
      interactions.tick
      interactions.stop_digging
    end

    expect(starts.map(&.location)).to eq([target, target])
  end

  it "does not extend either large fern half outside the block" do
    aim(1.05, 0.5)
    {"upper", "lower"}.each do |half|
      set_block(target, "large_fern", "half=#{half}")
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
    set_block(target, "large_fern", "half=lower")
    aim(0.5, 0.78)
    interactions.start_digging
    interactions.tick
    Rosegold::Clientbound::BlockChange.new(foreground, 0_u16).callback(bot_client)
    interactions.start_digging
    2.times { interactions.tick }

    expect(starts.map(&.location)).to eq([foreground, target])
  end
end
