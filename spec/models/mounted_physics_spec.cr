require "../spec_helper"

class Rosegold::MountedPhysicsClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def physics_for_test
    physics
  end

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    @sent_packets << packet
  end
end

Spectator.describe "Mounted player physics" do
  let(bot_client) { Rosegold::MountedPhysicsClient.new("localhost") }
  let(vehicle) do
    Rosegold::Entity.new(42_u32, UUID.random, 0_u32, Rosegold::Vec3d.new(0.5, -59.9375, 0.5),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
  end
  let(seated_position) { Rosegold::Vec3d.new(0.5, -60.35, 0.5) }

  after_each { Rosegold::Client.reset_protocol_version! }

  before_each do
    bot_client.player.entity_id = 300_u64
    bot_client.player.feet = seated_position
    bot_client.dimension_for_test.entities[42_u64] = vehicle
    bot_client.physics_for_test.paused = false
    Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
  end

  it "preserves the server-provided seat position when mounting" do
    expect(bot_client.player.feet).to eq(seated_position)
  end

  it "does not apply walking gravity or collision to a mounted player" do
    bot_client.player.velocity = Rosegold::Vec3d.new(0.1, -0.2, 0.1)

    25.times { bot_client.physics_for_test.tick }

    expect(bot_client.player.feet).to eq(seated_position)
    expect(bot_client.player.velocity).to eq(Rosegold::Vec3d::ORIGIN)
    expect(bot_client.player.on_ground?).to be_false
    expect(bot_client.sent_packets.size).to eq(25)
    expect(bot_client.sent_packets.all?(Rosegold::Serverbound::PlayerLook)).to be_true
  end

  it "sends look and input updates without claiming a walking position" do
    bot_client.player.look = Rosegold::Look.new(-90_f32, 15_f32)
    bot_client.physics_for_test.keys.press Rosegold::MovementKeys::Key::Forward

    bot_client.physics_for_test.tick

    look = bot_client.sent_packets.select(Rosegold::Serverbound::PlayerLook).last
    expect(look.yaw).to eq(-90_f32)
    expect(look.pitch).to eq(15_f32)
    input = bot_client.sent_packets.select(Rosegold::Serverbound::PlayerInput).last
    expect(input.flags.includes?(Rosegold::Serverbound::PlayerInput::Flag::Forward)).to be_true
    expect(bot_client.player.feet).to eq(seated_position)
  end

  it "completes a look action while mounted" do
    target = Rosegold::Look.new(-90_f32, 15_f32)
    completed = false
    spawn do
      bot_client.physics_for_test.look = target
      completed = true
    end
    Fiber.yield

    bot_client.physics_for_test.tick
    Fiber.yield

    expect(completed).to be_true
    expect(bot_client.player.look).to eq(target)
    expect(bot_client.player.feet).to eq(seated_position)
  end

  it "keeps the walking synchronization baseline unchanged while mounted" do
    physics = bot_client.physics_for_test
    physics.last_sent_feet = seated_position
    physics.last_sent_look = Rosegold::Look::SOUTH
    physics.last_sent_on_ground = true
    bot_client.player.look = Rosegold::Look.new(-90_f32, 15_f32)
    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

    25.times { physics.tick }

    expect(physics.last_sent_feet).to eq(seated_position)
    expect(physics.last_sent_look).to eq(Rosegold::Look::SOUTH)
    expect(physics.last_sent_on_ground).to be_true
  end

  it "still times out a movement action that makes no progress" do
    error : Exception? = nil
    completed = false
    spawn do
      begin
        bot_client.physics_for_test.move(seated_position + Rosegold::Vec3d.new(5, 0, 0), stuck_timeout_ticks: 3)
      rescue ex
        error = ex
      ensure
        completed = true
      end
    end
    Fiber.yield

    4.times { bot_client.physics_for_test.tick }
    Fiber.yield

    expect(completed).to be_true
    expect(error).to be_a(Rosegold::Physics::MovementStuck)
    expect(bot_client.player.feet).to eq(seated_position)
  ensure
    bot_client.physics_for_test.stop_moving
  end

  it "completes a movement action reached by the vehicle without snapping the seat position" do
    target = seated_position + Rosegold::Vec3d.new(1.05, 0, 0)
    completed = false
    spawn do
      bot_client.physics_for_test.move(target)
      completed = true
    end
    Fiber.yield
    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

    bot_client.physics_for_test.tick
    Fiber.yield

    expect(completed).to be_true
    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(1, 0, 0))
  ensure
    bot_client.physics_for_test.stop_moving
  end

  it "preserves the seat offset through absolute vehicle movement" do
    Rosegold::Clientbound::EntityPositionSync.new(42_u64, 2.5, -58.9375, 3.5,
      0.0, 0.0, 0.0, 0_f32, 0_f32, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(2, 1, 3))
  end

  it "does not apply a vehicle teleport twice after the server has already corrected the rider" do
    destination = seated_position + Rosegold::Vec3d.new(10, 1, 3)
    Rosegold::Clientbound::SynchronizePlayerPosition.new(destination.x, destination.y, destination.z,
      0_f32, 0_f32, 0, 1_u32).callback(bot_client)
    Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)

    Rosegold::Clientbound::EntityPositionSync.new(42_u64, 10.5, -58.9375, 3.5,
      0.0, 0.0, 0.0, 0_f32, 0_f32, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(destination)
  end

  it "reconciles relative vehicle movement after a rider correction" do
    destination = seated_position + Rosegold::Vec3d.new(1, 0.5, -1)
    Rosegold::Clientbound::SynchronizePlayerPosition.new(destination.x, destination.y, destination.z,
      0_f32, 0_f32, 0, 1_u32).callback(bot_client)

    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 2048_i16, -4096_i16, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(destination)
  end

  it "uses the new server-provided seat offset after remounting" do
    Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)
    new_seat = seated_position + Rosegold::Vec3d.new(0, 0.25, 0)
    bot_client.player.feet = new_seat
    Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)

    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(new_seat + Rosegold::Vec3d.new(1, 0, 0))
  end

  {% for protocol in Rosegold::ENABLED_PROTOCOLS.keys %}
    it "reconciles a moving minecart mounted ahead of its cached position on protocol {{protocol}}" do
      Rosegold::Client.protocol_version = {{protocol}}_u32
      Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)
      vehicle.entity_type = Rosegold::Entity.metadata_for_protocol.find! { |entry| entry.name == "minecart" }.id.to_u32
      server_seat = seated_position + Rosegold::Vec3d.new(1, 0.5, -1)
      bot_client.player.feet = server_seat

      Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
      expect(bot_client.player.feet).to eq(server_seat)

      Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 2048_i16, -4096_i16, true).callback(bot_client)

      expect(bot_client.player.feet).to eq(server_seat)
    end
  {% end %}

  it "follows relative vehicle movement" do
    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 2048_i16, -4096_i16, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(1, 0.5, -1))
  end

  it "follows relative vehicle movement with rotation without changing the player's look" do
    look = bot_client.player.look
    Rosegold::Clientbound::EntityPositionAndRotation.new(42_u64, 4096_i16, 2048_i16, -4096_i16,
      90_f32, 0_f32, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(1, 0.5, -1))
    expect(bot_client.player.look).to eq(look)
  end

  it "follows 26.3 stepped relative vehicle movement" do
    Rosegold::Client.protocol_version = 777_u32
    delta = Minecraft::EntityMovement::VecDelta.new([
      Minecraft::EntityMovement::DeltaStep.new(2048_i16, 0_i16, 0_i16, 1_u32),
      Minecraft::EntityMovement::DeltaStep.new(2048_i16, 2048_i16, -4096_i16, 2_u32),
    ])

    Rosegold::Clientbound::EntityPosition.new(42_u64, delta, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(1, 0.5, -1))
  end

  it "follows 26.3 stepped vehicle movement with rotation without changing the player's look" do
    Rosegold::Client.protocol_version = 777_u32
    look = bot_client.player.look
    delta = Minecraft::EntityMovement::VecDelta.new([
      Minecraft::EntityMovement::DeltaStep.new(2048_i16, 0_i16, 0_i16, 1_u32),
      Minecraft::EntityMovement::DeltaStep.new(2048_i16, 2048_i16, -4096_i16, 2_u32),
    ])

    Rosegold::Clientbound::EntityPositionAndRotation.new(42_u64, delta, 90_f32, 0_f32, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(1, 0.5, -1))
    expect(bot_client.player.look).to eq(look)
  end

  it "preserves the seat offset through a 26.3 vehicle position path" do
    Rosegold::Client.protocol_version = 777_u32
    path = Minecraft::EntityMovement::PositionPath.new([
      Minecraft::EntityMovement::PositionStep.new(vehicle.position + Rosegold::Vec3d.new(1, 0, 0), 1_u32),
      Minecraft::EntityMovement::PositionStep.new(vehicle.position + Rosegold::Vec3d.new(2, 1, 3), 2_u32),
    ])

    Rosegold::Clientbound::EntityPositionSync.new(42_u64, path, 0_f32, 0_f32, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position + Rosegold::Vec3d.new(2, 1, 3))
  end

  it "preserves another passenger's offset when its vehicle moves" do
    passenger = Rosegold::Entity.new(43_u32, UUID.random, 0_u32, vehicle.position + Rosegold::Vec3d.new(0, 0.75, 0),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    bot_client.dimension_for_test.entities[43_u64] = passenger
    vehicle.passenger_ids << 43_u32
    passenger_position = passenger.position

    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 2048_i16, -4096_i16, true).callback(bot_client)

    expect(passenger.position).to eq(passenger_position + Rosegold::Vec3d.new(1, 0.5, -1))
  end

  it "stops following the vehicle after dismounting" do
    Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)
    Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

    expect(bot_client.player.feet).to eq(seated_position)
  end

  it "resumes positional synchronization after dismounting" do
    bot_client.physics_for_test.tick
    Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)
    bot_client.sent_packets.clear

    bot_client.physics_for_test.tick

    expect(bot_client.sent_packets.any?(Rosegold::Serverbound::PlayerPosition)).to be_true
  end

  it "resumes positional synchronization when the vehicle is removed" do
    bot_client.physics_for_test.tick
    Rosegold::Clientbound::DestroyEntities.new([42_u64]).callback(bot_client)
    bot_client.sent_packets.clear

    bot_client.physics_for_test.tick

    expect(bot_client.sent_packets.any?(Rosegold::Serverbound::PlayerPosition)).to be_true
  end
end
