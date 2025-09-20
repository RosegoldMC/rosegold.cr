require "../../spec_helper"

Spectator.describe "PlayerPositionAndLook Serialization" do
  it "can read and write PlayerPositionAndLook packet with perfect equality" do
    # Set protocol version to match MC 1.21.8
    Rosegold::Client.protocol_version = 772_u32

    # Create a PlayerPositionAndLook packet with sample data
    original_packet = Rosegold::Serverbound::PlayerPositionAndLook.new(
      feet: Rosegold::Vec3d.new(100.5, 64.0, -200.25),
      look: Rosegold::Look.new(90.0_f32, -15.0_f32),
      on_ground: true,
      pushing_against_wall: false
    )

    # Write the packet to bytes
    packet_bytes = original_packet.write

    # Parse the packet back - skip packet ID (first byte is 0x1E)
    io = Minecraft::IO::Memory.new(packet_bytes[1..])
    parsed_packet = Rosegold::Serverbound::PlayerPositionAndLook.read(io)

    # Write the parsed packet back to bytes
    rewritten_bytes = parsed_packet.write

    # Compare the bytes for perfect roundtrip
    expect(rewritten_bytes).to eq(packet_bytes)
  end

  it "can parse PlayerPositionAndLook values correctly with protocol 772" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Test specific coordinate and angle values
    test_packet = Rosegold::Serverbound::PlayerPositionAndLook.new(
      feet: Rosegold::Vec3d.new(0.5, -60.0, 1.5),
      look: Rosegold::Look.new(-180.0_f32, 0.0_f32),
      on_ground: true,
      pushing_against_wall: false
    )

    # Serialize and parse back
    packet_bytes = test_packet.write
    io = Minecraft::IO::Memory.new(packet_bytes[1..])
    parsed = Rosegold::Serverbound::PlayerPositionAndLook.read(io)

    # Validate values
    expect(parsed.feet.x).to be_close(0.5, 0.001)
    expect(parsed.feet.y).to be_close(-60.0, 0.001)
    expect(parsed.feet.z).to be_close(1.5, 0.001)
    expect(parsed.look.yaw).to be_close(-180.0, 0.001)
    expect(parsed.look.pitch).to be_close(0.0, 0.001)
    expect(parsed.on_ground?).to eq(true)
    expect(parsed.pushing_against_wall?).to eq(false)
  end

  it "handles flag combinations correctly for MC 1.21.8+" do
    # Set protocol version for newer flag format
    Rosegold::Client.protocol_version = 772_u32

    # Test all flag combinations
    test_cases = [
      {on_ground: false, pushing: false, expected_flags: 0x00_u8},
      {on_ground: true, pushing: false, expected_flags: 0x01_u8},
      {on_ground: false, pushing: true, expected_flags: 0x02_u8},
      {on_ground: true, pushing: true, expected_flags: 0x03_u8},
    ]

    test_cases.each do |test_case|
      packet = Rosegold::Serverbound::PlayerPositionAndLook.new(
        feet: Rosegold::Vec3d.new(0.0, 0.0, 0.0),
        look: Rosegold::Look.new(0.0_f32, 0.0_f32),
        on_ground: test_case[:on_ground],
        pushing_against_wall: test_case[:pushing]
      )

      # Write and read back
      packet_bytes = packet.write
      io = Minecraft::IO::Memory.new(packet_bytes[1..])
      parsed = Rosegold::Serverbound::PlayerPositionAndLook.read(io)

      expect(parsed.on_ground?).to eq(test_case[:on_ground])
      expect(parsed.pushing_against_wall?).to eq(test_case[:pushing])

      # Check the actual flag byte in the packet
      expected_flags = test_case[:expected_flags]
      actual_flags = packet_bytes[-1] # Last byte should be flags
      expect(actual_flags).to eq(expected_flags)
    end
  end

  it "sanitizes invalid coordinate and angle values" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Test with extreme/invalid values
    packet_with_extremes = Rosegold::Serverbound::PlayerPositionAndLook.new(
      feet: Rosegold::Vec3d.new(50_000_000.0, -30_000_000.0, 50_000_000.0), # Beyond limits
      look: Rosegold::Look.new(720.0_f32, -270.0_f32),                      # Beyond -180 to 180 range
      on_ground: true,
      pushing_against_wall: false
    )

    # Values should be clamped/sanitized
    expect(packet_with_extremes.feet.x).to eq(30_000_000.0)          # Clamped to max
    expect(packet_with_extremes.feet.y).to eq(-20_000_000.0)         # Clamped to min
    expect(packet_with_extremes.feet.z).to eq(30_000_000.0)          # Clamped to max
    expect(packet_with_extremes.look.yaw).to be_close(0.0, 0.001)    # 720 - 360 - 360 = 0
    expect(packet_with_extremes.look.pitch).to be_close(90.0, 0.001) # -270 + 360 = 90

  end
end
