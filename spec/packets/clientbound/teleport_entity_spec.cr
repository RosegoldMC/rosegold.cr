require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::TeleportEntity do
  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  it "uses correct packet ID per protocol" do
    expect(Rosegold::Clientbound::TeleportEntity[772_u32]).to eq(0x76_u8)
    expect(Rosegold::Clientbound::TeleportEntity[773_u32]).to eq(0x7B_u8)
    expect(Rosegold::Clientbound::TeleportEntity[774_u32]).to eq(0x7B_u8)
    expect(Rosegold::Clientbound::TeleportEntity[775_u32]).to eq(0x7D_u8)
    expect(Rosegold::Clientbound::TeleportEntity[776_u32]).to eq(0x7D_u8)
  end

  it "supports exactly the five mapped protocols" do
    expect(Rosegold::Clientbound::TeleportEntity.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::TeleportEntity.supports_protocol?(776_u32)).to be_true
    expect(Rosegold::Clientbound::TeleportEntity.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::TeleportEntity.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x76_u8, 772_u32)).to eq(Rosegold::Clientbound::TeleportEntity)
    expect(play_state.get_clientbound_packet(0x7D_u8, 776_u32)).to eq(Rosegold::Clientbound::TeleportEntity)
  end

  describe "read/write round-trip" do
    it "preserves every field through a write/read cycle" do
      original = Rosegold::Clientbound::TeleportEntity.new(
        42_u64,
        1.5, -60.0, 2.25,
        0.1, -0.2, 0.3,
        90.0_f32, -45.0_f32,
        0b101010101_i32,
        true
      )

      bytes = original.write
      io = Minecraft::IO::Memory.new(bytes)
      io.read_byte
      read_back = Rosegold::Clientbound::TeleportEntity.read(io)

      expect(read_back.entity_id).to eq(42_u64)
      expect(read_back.x).to eq(1.5)
      expect(read_back.y).to eq(-60.0)
      expect(read_back.z).to eq(2.25)
      expect(read_back.velocity_x).to be_close(0.1, 0.0001)
      expect(read_back.velocity_y).to be_close(-0.2, 0.0001)
      expect(read_back.velocity_z).to be_close(0.3, 0.0001)
      expect(read_back.yaw).to eq(90.0_f32)
      expect(read_back.pitch).to eq(-45.0_f32)
      expect(read_back.relatives).to eq(0b101010101_i32)
      expect(read_back.on_ground?).to be_true
    end
  end

  describe "relative-bit resolution" do
    it "treats relatives == 0 as fully absolute" do
      packet = Rosegold::Clientbound::TeleportEntity.new(
        1_u64, 10.0, 20.0, 30.0, 1.0, 2.0, 3.0, 45.0_f32, 15.0_f32, 0_i32, false
      )
      current_pos = Rosegold::Vec3d.new(100.0, 200.0, 300.0)
      current_vel = Rosegold::Vec3d.new(9.0, 9.0, 9.0)

      resolved_pos = packet.resolved_position(current_pos)
      resolved_vel = packet.resolved_velocity(current_vel)

      expect(resolved_pos).to eq(Rosegold::Vec3d.new(10.0, 20.0, 30.0))
      expect(resolved_vel).to eq(Rosegold::Vec3d.new(1.0, 2.0, 3.0))
      expect(packet.resolved_yaw(50.0_f32)).to eq(45.0_f32)
      expect(packet.resolved_pitch(50.0_f32)).to eq(15.0_f32)
    end

    it "adds every field to the current value when all bits are set" do
      relatives = (1 << Rosegold::Clientbound::TeleportEntity::BIT_X) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_Y) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_Z) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_YAW) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_PITCH) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_DELTA_X) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_DELTA_Y) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_DELTA_Z)

      packet = Rosegold::Clientbound::TeleportEntity.new(
        1_u64, 1.0, 2.0, 3.0, 0.5, 0.5, 0.5, 10.0_f32, 5.0_f32, relatives, false
      )
      current_pos = Rosegold::Vec3d.new(100.0, 200.0, 300.0)
      current_vel = Rosegold::Vec3d.new(1.0, 1.0, 1.0)

      expect(packet.resolved_position(current_pos)).to eq(Rosegold::Vec3d.new(101.0, 202.0, 303.0))
      expect(packet.resolved_velocity(current_vel)).to eq(Rosegold::Vec3d.new(1.5, 1.5, 1.5))
      expect(packet.resolved_yaw(90.0_f32)).to eq(100.0_f32)
      expect(packet.resolved_pitch(20.0_f32)).to eq(25.0_f32)
    end

    it "resolves a mix of absolute and relative bits per axis" do
      relatives = (1 << Rosegold::Clientbound::TeleportEntity::BIT_X) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_PITCH) |
                  (1 << Rosegold::Clientbound::TeleportEntity::BIT_DELTA_Z)

      packet = Rosegold::Clientbound::TeleportEntity.new(
        1_u64, 5.0, 5.0, 5.0, 1.0, 1.0, 1.0, 0.0_f32, 5.0_f32, relatives, false
      )
      current_pos = Rosegold::Vec3d.new(100.0, 200.0, 300.0)
      current_vel = Rosegold::Vec3d.new(0.0, 0.0, 0.0)

      resolved_pos = packet.resolved_position(current_pos)
      expect(resolved_pos.x).to eq(105.0)
      expect(resolved_pos.y).to eq(5.0)
      expect(resolved_pos.z).to eq(5.0)

      resolved_vel = packet.resolved_velocity(current_vel)
      expect(resolved_vel.x).to eq(1.0)
      expect(resolved_vel.y).to eq(1.0)
      expect(resolved_vel.z).to eq(1.0)

      expect(packet.resolved_yaw(90.0_f32)).to eq(0.0_f32)
      expect(packet.resolved_pitch(90.0_f32)).to eq(95.0_f32)
    end
  end

  describe "callback" do
    it "updates a tracked entity's position, velocity, yaw, pitch, and on_ground" do
      c = client
      entity = Rosegold::Entity.new(
        7_u32,
        UUID.random,
        1_u32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0),
        0.0_f32, 0.0_f32, 0.0_f32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0)
      )
      c.dimension_for_test.entities[7_u64] = entity

      packet = Rosegold::Clientbound::TeleportEntity.new(
        7_u64, 12.0, 34.0, 56.0, 0.1, 0.2, 0.3, 90.0_f32, -30.0_f32, 0_i32, true
      )
      packet.callback(c)

      updated = c.dimension_for_test.entities[7_u64]
      expect(updated.position).to eq(Rosegold::Vec3d.new(12.0, 34.0, 56.0))
      expect(updated.velocity).to eq(Rosegold::Vec3d.new(0.1, 0.2, 0.3))
      expect(updated.yaw).to eq(90.0_f32)
      expect(updated.pitch).to eq(-30.0_f32)
      expect(updated.on_ground?).to be_true
    end

    it "no-ops when the entity is not tracked" do
      c = client
      packet = Rosegold::Clientbound::TeleportEntity.new(
        999_u64, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0_f32, 0.0_f32, 0_i32, false
      )

      packet.callback(c)

      expect(c.dimension_for_test.entities.has_key?(999_u64)).to be_false
    end
  end
end
