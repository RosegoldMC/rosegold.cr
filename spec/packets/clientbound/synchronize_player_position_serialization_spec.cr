require "../../spec_helper"

Spectator.describe "SynchronizePlayerPosition Serialization" do
  it "can read and write SynchronizePlayerPosition packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32
    
    # Captured SynchronizePlayerPosition packet data from log
    # 2025-08-05T04:22:43.889589Z   WARN - Packet bytes (62 bytes)
    hex_data = "41013fe0000000000000c04e0000000000003ff8000000000000000000000000000000000000000000000000000000000000c33400000000000000000000"
    
    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes
    
    puts "SynchronizePlayerPosition packet serialization test"
    puts "Original packet size: #{original_bytes.size} bytes"
    puts "Original bytes (first 32): #{original_bytes[0..31].hexstring}"
    
    # Parse the packet - skip packet ID (first byte is 0x41)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.read(io)
    
    puts "Parsed packet:"
    puts "  Teleport ID: #{packet.teleport_id}"
    puts "  Position: (#{packet.x_raw}, #{packet.y_raw}, #{packet.z_raw})"
    puts "  Velocity: (#{packet.velocity_x}, #{packet.velocity_y}, #{packet.velocity_z})"
    puts "  Angles: yaw=#{packet.yaw_raw}, pitch=#{packet.pitch_raw}"
    puts "  Relative flags: 0x#{packet.relative_flags.to_s(16).upcase.rjust(2, '0')}"
    
    # Write the packet back out
    rewritten_bytes = packet.write
    
    puts "Rewritten packet size: #{rewritten_bytes.size} bytes"
    puts "Rewritten bytes (first 32): #{rewritten_bytes[0..31].hexstring}"
    
    # Compare the bytes for perfect roundtrip
    if original_bytes == rewritten_bytes
      puts "✅ Perfect match! SynchronizePlayerPosition roundtrip successful."
      expect(rewritten_bytes).to eq(original_bytes)
    else
      puts "❌ Mismatch detected!"
      puts "Expected: #{original_bytes.hexstring}"
      puts "Got:      #{rewritten_bytes.hexstring}"
      expect(rewritten_bytes).to eq(original_bytes)
    end
  end
  
  it "can parse minecraft:synchronize_player_position values correctly" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32
    
    # Same packet data as above test
    hex_data = "41013fe0000000000000c04e0000000000003ff8000000000000000000000000000000000000000000000000000000000000c33400000000000000000000"
    original_bytes = hex_data.hexbytes
    
    # Parse the packet
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.read(io)
    
    # Validate specific values from the hex data:
    # Teleport ID=1, Pos=(0.5, -60.0, 1.5), Velocity=(0,0,0), Yaw=-180°, Pitch=0°, Flags=0
    expect(packet.teleport_id).to eq(1_u32)
    expect(packet.x_raw).to be_close(0.5, 0.001)
    expect(packet.y_raw).to be_close(-60.0, 0.001)
    expect(packet.z_raw).to be_close(1.5, 0.001)
    expect(packet.velocity_x).to eq(0.0)
    expect(packet.velocity_y).to eq(0.0)
    expect(packet.velocity_z).to eq(0.0)
    expect(packet.yaw_raw).to be_close(-180.0, 0.001)
    expect(packet.pitch_raw).to eq(0.0)
    expect(packet.relative_flags).to eq(0_u8)
    
    puts "✅ SynchronizePlayerPosition values validated successfully"
  end
end