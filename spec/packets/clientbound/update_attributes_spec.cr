require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::UpdateAttributes do
  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  it "uses correct packet ID per protocol" do
    expect(Rosegold::Clientbound::UpdateAttributes[772_u32]).to eq(0x7C_u8)
    expect(Rosegold::Clientbound::UpdateAttributes[773_u32]).to eq(0x81_u8)
    expect(Rosegold::Clientbound::UpdateAttributes[774_u32]).to eq(0x81_u8)
    expect(Rosegold::Clientbound::UpdateAttributes[775_u32]).to eq(0x83_u8)
    expect(Rosegold::Clientbound::UpdateAttributes[776_u32]).to eq(0x83_u8)
  end

  it "supports exactly the five mapped protocols" do
    expect(Rosegold::Clientbound::UpdateAttributes.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::UpdateAttributes.supports_protocol?(776_u32)).to be_true
    expect(Rosegold::Clientbound::UpdateAttributes.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::UpdateAttributes.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x7C_u8, 772_u32)).to eq(Rosegold::Clientbound::UpdateAttributes)
    expect(play_state.get_clientbound_packet(0x83_u8, 776_u32)).to eq(Rosegold::Clientbound::UpdateAttributes)
  end

  describe "read/write round-trip" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    it "preserves entity id, bases, and modifiers across operations" do
      original = Rosegold::Clientbound::UpdateAttributes.new(
        7_u64,
        [
          Rosegold::AttributeSnapshot.new(22_u32, 0.1, [
            Rosegold::AttributeModifier.new("minecraft:sprinting", 0.3, 2_u8),
            Rosegold::AttributeModifier.new("minecraft:base_boost", 0.05, 0_u8),
          ]),
          Rosegold::AttributeSnapshot.new(2_u32, 4.0, [] of Rosegold::AttributeModifier),
        ]
      )

      io = Minecraft::IO::Memory.new(original.write)
      io.read_var_int
      read_back = Rosegold::Clientbound::UpdateAttributes.read(io)

      expect(read_back.entity_id).to eq(7_u64)
      expect(read_back.attribute_snapshots.size).to eq(2)

      speed = read_back.attribute_snapshots[0]
      expect(speed.attribute_id).to eq(22_u32)
      expect(speed.base).to be_close(0.1, 1e-9)
      expect(speed.modifiers.size).to eq(2)
      expect(speed.modifiers[0].id).to eq("minecraft:sprinting")
      expect(speed.modifiers[0].amount).to be_close(0.3, 1e-9)
      expect(speed.modifiers[0].operation).to eq(2_u8)
      expect(speed.modifiers[1].id).to eq("minecraft:base_boost")
      expect(speed.modifiers[1].operation).to eq(0_u8)

      damage = read_back.attribute_snapshots[1]
      expect(damage.attribute_id).to eq(2_u32)
      expect(damage.base).to be_close(4.0, 1e-9)
      expect(damage.modifiers).to be_empty
    end
  end

  describe "callback" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    it "replaces attribute entries on a tracked entity" do
      c = client
      entity = Rosegold::Entity.new(
        7_u32, UUID.random, 1_u32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0),
        0.0_f32, 0.0_f32, 0.0_f32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0)
      )
      c.dimension_for_test.entities[7_u64] = entity

      Rosegold::Clientbound::UpdateAttributes.new(
        7_u64, [Rosegold::AttributeSnapshot.new(22_u32, 0.15, [] of Rosegold::AttributeModifier)]
      ).callback(c)

      expect(c.dimension_for_test.entities[7_u64].attributes[22_u32].base).to eq(0.15)
    end

    it "stores attributes on the player when the packet targets the bot's entity" do
      c = client
      c.player.entity_id = 99_u64

      Rosegold::Clientbound::UpdateAttributes.new(
        99_u64, [Rosegold::AttributeSnapshot.new(22_u32, 0.2, [] of Rosegold::AttributeModifier)]
      ).callback(c)

      expect(c.player.movement_speed_attribute.try(&.base)).to eq(0.2)
    end

    it "no-ops for an untracked entity that is not the bot" do
      c = client
      c.player.entity_id = 1_u64

      Rosegold::Clientbound::UpdateAttributes.new(
        555_u64, [Rosegold::AttributeSnapshot.new(22_u32, 0.3, [] of Rosegold::AttributeModifier)]
      ).callback(c)

      expect(c.dimension_for_test.entities.has_key?(555_u64)).to be_false
      expect(c.player.attributes).to be_empty
    end
  end
end
