require "../../spec_helper"

Spectator.describe "PlayerAbilities Serialization" do
  it "can read and write PlayerAbilities packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Provided PlayerAbilities packet data: Bytes[57, 0, 61, 76, 204, 205, 61, 204, 204, 205]
    # Packet ID: 57 (0x39), Flags: 0, Flying Speed: 4 bytes, FOV Modifier: 4 bytes
    original_bytes = Bytes[57, 0, 61, 76, 204, 205, 61, 204, 204, 205]

    # Parse the packet - skip packet ID (first byte is 0x39/57)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::PlayerAbilities.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes for perfect roundtrip
    expect(rewritten_bytes).to eq(original_bytes)
  end

  it "can parse PlayerAbilities values correctly" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Same packet data as above test
    original_bytes = Bytes[57, 0, 61, 76, 204, 205, 61, 204, 204, 205]

    # Parse the packet
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::PlayerAbilities.read(io)

    # Validate specific values from the packet bytes:
    # Flags=0 (no abilities), Flying Speed and FOV Modifier need to be decoded from IEEE 754
    expect(packet.flags).to eq(0_u8)
    expect(packet.invulnerable?).to eq(false)
    expect(packet.flying?).to eq(false)
    expect(packet.allow_flying?).to eq(false)
    expect(packet.creative_mode?).to eq(false)

    # The float values should match the decoded IEEE 754 values
    # Bytes [61, 76, 204, 205] = 0.05 and [61, 204, 204, 205] = 0.1 as Float32
    expect(packet.flying_speed).to be_close(0.05, 0.001)
    expect(packet.field_of_view_modifier).to be_close(0.1, 0.001)
  end

  it "can create PlayerAbilities packets with different flag combinations" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Test case 1: Creative mode with all abilities
    packet1 = Rosegold::Clientbound::PlayerAbilities.new(
      flags: 0x0F_u8, # All flags set (0x01|0x02|0x04|0x08)
      flying_speed: 0.05_f32,
      field_of_view_modifier: 0.1_f32
    )

    expect(packet1.invulnerable?).to eq(true)
    expect(packet1.flying?).to eq(true)
    expect(packet1.allow_flying?).to eq(true)
    expect(packet1.creative_mode?).to eq(true)

    # Test serialization roundtrip
    bytes1 = packet1.write
    io1 = Minecraft::IO::Memory.new(bytes1[1..])
    parsed1 = Rosegold::Clientbound::PlayerAbilities.read(io1)

    expect(parsed1.flags).to eq(0x0F_u8)
    expect(parsed1.flying_speed).to be_close(0.05, 0.001)
    expect(parsed1.field_of_view_modifier).to be_close(0.1, 0.001)

    # Test case 2: Only allow flying (spectator mode)
    packet2 = Rosegold::Clientbound::PlayerAbilities.new(
      flags: 0x04_u8, # Only allow flying
      flying_speed: 0.02_f32,
      field_of_view_modifier: 0.08_f32
    )

    expect(packet2.invulnerable?).to eq(false)
    expect(packet2.flying?).to eq(false)
    expect(packet2.allow_flying?).to eq(true)
    expect(packet2.creative_mode?).to eq(false)
  end
end
