require "../spec_helper"

class Rosegold::Interactions
  def reached_entity_for_mounted_test
    reach_block_or_entity_unified.as?(Entity)
  end

  def reached_block_for_mounted_test
    reach_block_or_entity_unified.as?(ReachedBlock).try(&.block)
  end
end

class Rosegold::MountedInteractionClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def interactions_for_test
    interactions
  end

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    @sent_packets << packet
  end
end

Spectator.describe "Mounted entity raytracing" do
  let(protocol) { Rosegold::Client::LATEST_PROTOCOL }
  let(bot_client) { Rosegold::MountedInteractionClient.new("localhost") }
  let(minecart_type) { Rosegold::Entity.metadata_for_protocol.find! { |entry| entry.name == "minecart" }.id.to_u32 }
  let(vehicle) do
    Rosegold::Entity.new(42_u32, UUID.random, minecart_type, Rosegold::Vec3d.new(0.5, -59.9375, 0.5),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
  end
  let(other_cart) do
    Rosegold::Entity.new(43_u32, UUID.random, minecart_type, Rosegold::Vec3d.new(0.5, -61, 0.5),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
  end
  let(interactions) { Rosegold::Interactions.new(bot_client) }

  after_each { Rosegold::Client.reset_protocol_version! }

  before_each do
    Rosegold::Client.protocol_version = protocol
    bot_client.player.entity_id = 300_u64
    bot_client.player.feet = Rosegold::Vec3d.new(0.5, -60.35, 0.5)
    bot_client.player.look = Rosegold::Look.new(0_f32, 90_f32)
    bot_client.dimension_for_test.entities[42_u64] = vehicle
    bot_client.dimension_for_test.entities[43_u64] = other_cart
    Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
  end

  it "looks past its own minecart to another entity below it" do
    expect(interactions.reached_entity_for_mounted_test).to eq(other_cart)
  end

  it "looks through its own minecart to the block underneath" do
    dimension = bot_client.dimension_for_test
    dimension.entities.delete(43_u64)
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
    stone = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }.min_state_id
    dimension.set_block_state(0, -61, 0, stone)

    expect(interactions.reached_block_for_mounted_test).to eq(Rosegold::Vec3i.new(0, -61, 0))
  end

  it "excludes the mount from entity-only raycasts" do
    reached = bot_client.dimension_for_test.raycast_entity(bot_client.player.eyes, bot_client.player.look.to_vec3,
      3.0, bot_client.player.entity_id.to_u32)

    expect(reached).to eq(other_cart)
  end

  {% for protocol in Rosegold::ENABLED_PROTOCOLS.keys %}
    context "protocol {{protocol}}" do
      let(protocol) { {{protocol}}_u32 }

      it "attacks the aimed entity instead of the ridden minecart" do
        bot_client.interactions_for_test.start_digging
        bot_client.interactions_for_test.tick
        bot_client.interactions_for_test.stop_digging

        {% if protocol >= 775 %}
          attacks = bot_client.sent_packets.select(Rosegold::Serverbound::Attack)
          expect(bot_client.sent_packets.select(Rosegold::Serverbound::InteractEntity)).to be_empty
        {% else %}
          attacks = bot_client.sent_packets.select(Rosegold::Serverbound::InteractEntity)
          expect(bot_client.sent_packets.select(Rosegold::Serverbound::Attack)).to be_empty
        {% end %}
        expect(attacks.size).to eq(1)
        {% if protocol < 775 %}
          expect(attacks.first.action).to eq(Rosegold::Serverbound::InteractEntity::Action::Attack)
        {% end %}
        expect(attacks.first.entity_id).to eq(other_cart.entity_id)
      end
    end
  {% end %}

  it "keeps unscoped entity raycasts unchanged" do
    reached = bot_client.dimension_for_test.raycast_entity(bot_client.player.eyes, bot_client.player.look.to_vec3, 3.0)

    expect(reached).to eq(vehicle)
  end

  it "can target the former vehicle after dismounting" do
    Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)

    expect(interactions.reached_entity_for_mounted_test).to eq(vehicle)
  end

  it "can target its own vehicle when its eyes are inside the vehicle bounds" do
    bot_client.player.feet = vehicle.position.up(0.25 - Rosegold::Player::DEFAULT_EYE_HEIGHT)

    expect(interactions.reached_entity_for_mounted_test).to eq(vehicle)
  end

  it "can target its own vehicle from inside with an entity-only raycast" do
    bot_client.player.feet = vehicle.position.up(0.25 - Rosegold::Player::DEFAULT_EYE_HEIGHT)
    reached = bot_client.dimension_for_test.raycast_entity(bot_client.player.eyes, bot_client.player.look.to_vec3,
      3.0, bot_client.player.entity_id.to_u32)

    expect(reached).to eq(vehicle)
  end
end
