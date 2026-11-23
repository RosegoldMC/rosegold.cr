require "../spec_helper"

class Rosegold::Interactions
  def target_for_test
    case hit = reach_block_or_entity
    when ReachedBlock  then hit.block
    when ReachedEntity then hit.entity
    end
  end

  def entity_intercept_for_test
    reach_block_or_entity.as?(ReachedEntity).try(&.intercept)
  end
end

class InteractionTargetingSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
  end

  def self.server_protocol
    Rosegold::Client.status(MC_TEST_HOST, MC_TEST_PORT.to_u16).json_response["version"]["protocol"].as_i.to_u32
  rescue Socket::ConnectError
    Rosegold::Client::LATEST_PROTOCOL
  end
end

INTERACTION_TARGETING_PROTOCOL = InteractionTargetingSpecClient.server_protocol

Spectator.describe "Shared interaction targeting" do
  let(bot_client) { InteractionTargetingSpecClient.new("localhost") }
  let(dimension) { bot_client.dimension_for_test }
  let(player) { bot_client.player }
  let(interactions) { Rosegold::Interactions.new(bot_client) }
  let(foreground) { Rosegold::Vec3i.new(0, 0, 2) }
  let(stone) { Rosegold::MCData.default.blocks.find! { |entry| entry.id_str == "stone" }.min_state_id }

  before_each do
    Rosegold::Client.protocol_version = INTERACTION_TARGETING_PROTOCOL
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
    player.entity_id = 100_u64
    player.feet = Rosegold::Vec3d.new(0.5, 0.9 - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    player.look = Rosegold::Look::SOUTH
  end

  after_each { Rosegold::Client.reset_protocol_version! }

  def entity_at(z : Float64, name = "zombie", id = 1_u32)
    type = Rosegold::Entity.metadata_for_protocol.find! { |entry| entry.name == name }.id.to_u32
    entity = Rosegold::Entity.new(id, UUID.random, type, Rosegold::Vec3d.new(0.5, 0.0, z),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    dimension.entities[id.to_u64] = entity
    entity
  end

  def set_ranges(block : Float64, entity : Float64)
    modern = Rosegold::Client.protocol_version >= 776_u32
    player.apply_attribute_snapshots([
      Rosegold::AttributeSnapshot.new(modern ? 8_u32 : 6_u32, block),
      Rosegold::AttributeSnapshot.new(modern ? 13_u32 : 10_u32, entity),
    ])
  end

  def use_targets
    bot_client.sent_packets.clear
    input = Rosegold::Interactions.new(bot_client)
    input.tap_using_hand
    input.tick
    bot_client.sent_packets.compact_map do |packet|
      case packet
      when Rosegold::Serverbound::InteractEntity       then packet.entity_id
      when Rosegold::Serverbound::PlayerBlockPlacement then packet.location
      end
    end.uniq!
  end

  def attack_targets
    bot_client.sent_packets.clear
    input = Rosegold::Interactions.new(bot_client)
    input.start_digging
    input.tick
    bot_client.sent_packets.compact_map do |packet|
      case packet
      when Rosegold::Serverbound::Attack         then packet.entity_id
      when Rosegold::Serverbound::InteractEntity then packet.entity_id if packet.action.attack?
      when Rosegold::Serverbound::PlayerAction   then packet.location if packet.status.start?
      end
    end
  end

  it "uses the predicted foreground for use and attack until a rejected break is acknowledged" do
    entity = entity_at(3.0)
    dimension.set_block_state(foreground, stone)
    expect(use_targets).to eq([foreground])
    expect(attack_targets).to eq([foreground])

    expect(dimension.predict_block_break(foreground, 100)).to be_true
    expect(dimension.block_state(foreground)).to eq(stone)
    expect(use_targets).to eq([entity.entity_id.to_u64])
    expect(attack_targets).to eq([entity.entity_id.to_u64])

    Rosegold::Clientbound::AcknowledgeBlockChange.new(100).callback(bot_client)
    expect(use_targets).to eq([foreground])
    expect(attack_targets).to eq([foreground])
  end

  it "traces from the eyes out to a longer synced entity range" do
    set_ranges(block: 2.0, entity: 6.0)
    entity = entity_at(5.5)

    expect(interactions.target_for_test).to eq(entity)
    expect(interactions.entity_intercept_for_test.try(&.z)).to eq(entity.bounding_box.min.z)
  end

  it "traces out to a longer synced block range" do
    set_ranges(block: 6.0, entity: 2.0)
    distant = Rosegold::Vec3i.new(0, 0, 6)
    dimension.set_block_state(distant, stone)

    expect(interactions.target_for_test).to eq(distant)
  end

  it "misses when a nearer entity is outside its own range, even with a reachable block behind it" do
    set_ranges(block: 5.0, entity: 1.0)
    entity_at(2.5)
    dimension.set_block_state(Rosegold::Vec3i.new(0, 0, 4), stone)

    expect(interactions.target_for_test).to be_nil
  end

  it "misses when a nearer block is outside its own range, even with a reachable entity behind it" do
    set_ranges(block: 1.0, entity: 5.0)
    dimension.set_block_state(foreground, stone)
    entity_at(4.0)

    expect(interactions.target_for_test).to be_nil
  end

  it "excludes hits exactly at either interaction range" do
    dimension.set_block_state(foreground, stone)
    set_ranges(block: 1.5, entity: 5.0)
    expect(interactions.target_for_test).to be_nil

    dimension.set_block_state(foreground, 0_u16)
    entity = entity_at(2.5)
    set_ranges(block: 5.0, entity: entity.bounding_box.min.z - player.eyes.z)
    expect(interactions.target_for_test).to be_nil
  end

  it "prefers a block whose face ties an entity's hit distance" do
    entity = entity_at(2.25, "armor_stand")
    dimension.set_block_state(foreground, stone)

    expect(entity.bounding_box.min.z).to eq(2.0)
    expect(interactions.target_for_test).to eq(foreground)
  end

  it "uses the eyes as the intercept when they are inside a pickable entity" do
    entity = entity_at(0.5)
    dimension.set_block_state(foreground, stone)

    expect(interactions.target_for_test).to eq(entity)
    expect(interactions.entity_intercept_for_test).to eq(player.eyes)
  end

  it "lets a later entity replace an ordinary containing hit" do
    entity_at(0.5)
    second = entity_at(3.0, id: 2_u32)

    expect(interactions.target_for_test).to eq(second)
  end

  it "keeps a containing entity when a later entity is hidden behind the first block" do
    containing = entity_at(0.5)
    entity_at(3.0, id: 2_u32)
    dimension.set_block_state(foreground, stone)

    expect(interactions.target_for_test).to eq(containing)
    expect(interactions.entity_intercept_for_test).to eq(player.eyes)
    expect(use_targets).to eq([containing.entity_id.to_u64])
    expect(attack_targets).to eq([containing.entity_id.to_u64])
  end

  it "skips nonpickable entities even when the eyes are inside them" do
    marker = entity_at(0.5, "item")
    marker.position = player.eyes.down(0.1)
    dimension.set_block_state(foreground, stone)

    expect(interactions.target_for_test).to eq(foreground)
  end

  it "looks past a marker armor stand but still picks an unflagged armor stand" do
    stand = entity_at(1.5, "armor_stand")
    dimension.set_block_state(foreground, stone)
    expect(interactions.target_for_test).to eq(stand)

    stand.tracked_data[15_u8] = 0x10_u8
    expect(interactions.target_for_test).to eq(foreground)

    stand.tracked_data[15_u8] = 0x01_u8
    expect(interactions.target_for_test).to eq(stand)
  end

  it "looks past spectator players without changing public entity raycasts" do
    other = entity_at(1.5, "player")
    dimension.set_block_state(foreground, stone)
    expect(interactions.target_for_test).to eq(other)

    bot_client.player_list[other.uuid] = Rosegold::PlayerList::Entry.new(other.uuid, gamemode: 3_i8)
    expect(interactions.target_for_test).to eq(foreground)
    expect(dimension.raycast_entity(player.eyes, player.look.to_vec3, 3.0)).to eq(other)
  end

  sample Rosegold::Client::SUPPORTED_PROTOCOLS do |protocol|
    it "uses the registry's entity reach attribute and clamps it" do
      Rosegold::Client.protocol_version = protocol
      expect(player.entity_interaction_range).to eq(3.0)
      player.gamemode = 1_i8
      expect(player.entity_interaction_range).to eq(5.0)

      id = protocol >= 776_u32 ? 13_u32 : 10_u32
      modifier = Rosegold::AttributeModifier.new("test:reach", 2.0, 0_u8)
      player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 10.0, [modifier])])
      expect(player.entity_interaction_range).to eq(12.0)
      player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 65.0)])
      expect(player.entity_interaction_range).to eq(64.0)
      player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, -1.0)])
      expect(player.entity_interaction_range).to eq(0.0)
    end
  end
end
