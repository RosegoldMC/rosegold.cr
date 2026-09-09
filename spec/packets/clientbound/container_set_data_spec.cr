require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::ContainerSetData do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::ContainerSetData[772_u32]).to eq(0x13_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Clientbound::ContainerSetData[773_u32]).to eq(0x13_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Clientbound::ContainerSetData[774_u32]).to eq(0x13_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Clientbound::ContainerSetData[775_u32]).to eq(0x13_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Clientbound::ContainerSetData[776_u32]).to eq(0x13_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Clientbound::ContainerSetData.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::ContainerSetData.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::ContainerSetData.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x13_u8, 772_u32)).to eq(Rosegold::Clientbound::ContainerSetData)
  end

  describe "packet parsing" do
    it "reads container_id, property, and value" do
      io = Minecraft::IO::Memory.new
      io.write 2_u32        # container_id (VarInt)
      io.write_full 14_i16  # property (Short)
      io.write_full 200_i16 # value (Short)
      io.pos = 0

      packet = Rosegold::Clientbound::ContainerSetData.read(io)

      expect(packet.container_id).to eq(2_u32)
      expect(packet.property_id).to eq(14_i16)
      expect(packet.value).to eq(200_i16)
    end

    it "reads negative values" do
      io = Minecraft::IO::Memory.new
      io.write 0_u32
      io.write_full 0_i16
      io.write_full(-1_i16)
      io.pos = 0

      packet = Rosegold::Clientbound::ContainerSetData.read(io)

      expect(packet.value).to eq(-1_i16)
    end
  end

  describe "round-trip serialization" do
    it "can write and read a container property update" do
      original_packet = Rosegold::Clientbound::ContainerSetData.new(3_u32, 15_i16, 90_i16)

      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)
      io.read_byte # skip packet ID

      read_packet = Rosegold::Clientbound::ContainerSetData.read(io)

      expect(read_packet.container_id).to eq(3_u32)
      expect(read_packet.property_id).to eq(15_i16)
      expect(read_packet.value).to eq(90_i16)
    end
  end

  describe "callback behavior" do
    let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

    it "stores the property on the container menu when the container id matches" do
      packet = Rosegold::Clientbound::ContainerSetData.new(client.container_menu.id.to_u32, 0_i16, 42_i16)

      packet.callback(client)

      expect(client.container_menu.properties[0_i16]).to eq(42_i16)
    end

    it "drops the update when the container id does not match" do
      mismatched_id = client.container_menu.id.to_u32 + 1_u32
      packet = Rosegold::Clientbound::ContainerSetData.new(mismatched_id, 0_i16, 42_i16)

      packet.callback(client)

      expect(client.container_menu.properties.has_key?(0_i16)).to be_false
    end
  end
end
