require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetEntityData do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SetEntityData[772_u32]).to eq(0x5C_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Clientbound::SetEntityData[773_u32]).to eq(0x61_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Clientbound::SetEntityData[774_u32]).to eq(0x61_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Clientbound::SetEntityData[775_u32]).to eq(0x63_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Clientbound::SetEntityData[776_u32]).to eq(0x63_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Clientbound::SetEntityData.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::SetEntityData.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::SetEntityData.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x5C_u8, 772_u32)).to eq(Rosegold::Clientbound::SetEntityData)
  end

  describe "serializer tables" do
    it "keeps indices 0-15 identical across protocols" do
      [772_u32, 773_u32, 775_u32].each do |protocol|
        expect(Rosegold::EntityMetadata.serializer_for(0_u32, protocol)).to eq(:byte)
        expect(Rosegold::EntityMetadata.serializer_for(6_u32, protocol)).to eq(:opt_text_component)
        expect(Rosegold::EntityMetadata.serializer_for(8_u32, protocol)).to eq(:boolean)
      end
    end

    it "has an nbt serializer at 16 on 772 only" do
      expect(Rosegold::EntityMetadata.serializer_for(16_u32, 772_u32)).to eq(:nbt)
      expect(Rosegold::EntityMetadata.serializer_for(16_u32, 773_u32)).to eq(:particle)
    end

    it "inserts cat_sound_variant at 22 on 775, shifting cow_variant to 23" do
      expect(Rosegold::EntityMetadata.serializer_for(22_u32, 773_u32)).to eq(:cow_variant)
      expect(Rosegold::EntityMetadata.serializer_for(22_u32, 775_u32)).to eq(:cat_sound_variant)
      expect(Rosegold::EntityMetadata.serializer_for(23_u32, 775_u32)).to eq(:cow_variant)
    end
  end

  describe "packet parsing" do
    it "decodes entity flags and a custom name on protocol 772" do
      Rosegold::Client.protocol_version = 772_u32

      io = Minecraft::IO::Memory.new
      io.write 42_u32       # entity_id
      io.write_byte 0_u8    # index 0 (entity flags)
      io.write 0_u32        # serializer: byte
      io.write_byte 0x48_u8 # sprinting (0x08) + glowing (0x40)
      io.write_byte 2_u8    # index 2 (custom_name)
      io.write 6_u32        # serializer: opt_text_component
      io.write true         # present
      io.write Rosegold::TextComponent.new("Bob")
      io.write_byte 0xFF_u8 # terminator
      io.pos = 0

      packet = Rosegold::Clientbound::SetEntityData.read(io)

      expect(packet.entity_id).to eq(42_u64)
      expect(packet.entries.size).to eq(2)
      values = packet.values
      expect(values[0_u8]).to eq(0x48_u8)
      name = values[2_u8]
      expect(name).to be_a(Rosegold::TextComponent)
      expect(name.as(Rosegold::TextComponent).text).to eq("Bob")
    end

    it "decodes an nbt tracked value on protocol 772" do
      Rosegold::Client.protocol_version = 772_u32

      tag = Minecraft::NBT::CompoundTag.new(
        {"k" => Minecraft::NBT::IntTag.new(7).as(Minecraft::NBT::Tag)} of String => Minecraft::NBT::Tag)

      io = Minecraft::IO::Memory.new
      io.write 1_u32
      io.write_byte 5_u8 # index
      io.write 16_u32    # serializer: nbt (772 only)
      io.write_byte tag.tag_type
      tag.write io
      io.write_byte 0xFF_u8
      io.pos = 0

      packet = Rosegold::Clientbound::SetEntityData.read(io)

      expect(packet.values[5_u8]).to be_a(Minecraft::NBT::Tag)
    end

    it "decodes the same shared fields on protocol 773 despite the shifted packet id" do
      Rosegold::Client.protocol_version = 773_u32

      io = Minecraft::IO::Memory.new
      io.write 9_u32
      io.write_byte 0_u8
      io.write 0_u32
      io.write_byte 0x20_u8 # invisible
      io.write_byte 0xFF_u8
      io.pos = 0

      packet = Rosegold::Clientbound::SetEntityData.read(io)

      expect(packet.values[0_u8]).to eq(0x20_u8)
    end

    it "decodes a Slot at index 8" do
      Rosegold::Client.protocol_version = 772_u32

      io = Minecraft::IO::Memory.new
      io.write 3_u32
      io.write_byte 8_u8 # item entity's item_stack
      io.write 7_u32     # serializer: slot
      io.write Rosegold::Slot.new(4_u32, 55_u32)
      io.write_byte 0xFF_u8
      io.pos = 0

      packet = Rosegold::Clientbound::SetEntityData.read(io)

      slot = packet.values[8_u8]
      expect(slot).to be_a(Rosegold::Slot)
      expect(slot.as(Rosegold::Slot).item_id_int).to eq(55_u32)
    end

    it "degrades to RawPacket when a particle serializer is encountered" do
      Rosegold::Client.protocol_version = 772_u32

      buffer = Minecraft::IO::Memory.new
      buffer.write 0x5C_u32 # packet id
      buffer.write 1_u32    # entity_id
      buffer.write_byte 0_u8
      buffer.write 17_u32 # serializer: particle (772) — no codec, must raise

      decoded = Rosegold::Connection.decode_clientbound_packet(
        buffer.to_slice, Rosegold::ProtocolState::PLAY, 772_u32)

      expect(decoded).to be_a(Rosegold::Clientbound::RawPacket)
    end
  end

  describe "callback behavior" do
    let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

    def tracked_entity
      Rosegold::Entity.new(
        7_u32, UUID.random, 1_u32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0),
        0.0_f32, 0.0_f32, 0.0_f32,
        Rosegold::Vec3d.new(0.0, 0.0, 0.0))
    end

    it "merges partial updates rather than replacing tracked_data" do
      entity = tracked_entity
      entity.tracked_data[9_u8] = "keep"
      entity.tracked_data[0_u8] = 0x01_u8
      client.dimension_for_test.entities[7_u64] = entity

      packet = Rosegold::Clientbound::SetEntityData.new(
        7_u64, [Rosegold::Clientbound::SetEntityData::Entry.new(0_u8, 0_u32, 0x08_u8.as(Rosegold::Entity::TrackedValue))])
      packet.callback(client)

      expect(entity.tracked_data[0_u8]).to eq(0x08_u8)
      expect(entity.tracked_data[9_u8]).to eq("keep")
      expect(entity.sprinting?).to be_true
    end

    it "no-ops for an unknown entity" do
      packet = Rosegold::Clientbound::SetEntityData.new(
        123_u64, [Rosegold::Clientbound::SetEntityData::Entry.new(0_u8, 0_u32, 0x01_u8.as(Rosegold::Entity::TrackedValue))])

      expect { packet.callback(client) }.not_to raise_error
    end
  end

  describe "round-trip serialization" do
    it "preserves the decodable serializer subset" do
      Rosegold::Client.protocol_version = 772_u32

      entries = [
        Rosegold::Clientbound::SetEntityData::Entry.new(0_u8, 0_u32, 0x08_u8.as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(1_u8, 1_u32, 300_u32.as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(3_u8, 3_u32, 2.5_f32.as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(4_u8, 4_u32, "hi".as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(8_u8, 7_u32, Rosegold::Slot.new(2_u32, 9_u32).as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(11_u8, 9_u32, {1.0_f32, 2.0_f32, 3.0_f32}.as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(12_u8, 10_u32, Rosegold::Vec3i.new(4, 5, 6).as(Rosegold::Entity::TrackedValue)),
        Rosegold::Clientbound::SetEntityData::Entry.new(20_u8, 19_u32, [1_u32, 2_u32, 3_u32].as(Rosegold::Entity::TrackedValue)),
      ]
      original = Rosegold::Clientbound::SetEntityData.new(88_u64, entries)

      io = Minecraft::IO::Memory.new(original.write)
      io.read_byte # skip packet id

      read = Rosegold::Clientbound::SetEntityData.read(io)

      expect(read.entity_id).to eq(88_u64)
      expect(read.entries.size).to eq(8)
      values = read.values
      expect(values[0_u8]).to eq(0x08_u8)
      expect(values[1_u8]).to eq(300_u32)
      expect(values[3_u8]).to eq(2.5_f32)
      expect(values[4_u8]).to eq("hi")
      expect(values[8_u8].as(Rosegold::Slot).item_id_int).to eq(9_u32)
      expect(values[11_u8]).to eq({1.0_f32, 2.0_f32, 3.0_f32})
      expect(values[12_u8].as(Rosegold::Vec3i)).to eq(Rosegold::Vec3i.new(4, 5, 6))
      expect(values[20_u8]).to eq([1_u32, 2_u32, 3_u32])
    end
  end
end
