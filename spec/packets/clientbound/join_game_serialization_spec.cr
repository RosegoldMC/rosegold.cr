require "../../spec_helper"

Spectator.describe "JoinGame Serialization" do
  it "can read and write JoinGame packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32
    
    # Captured JoinGame packet data from log
    # 2025-08-05T00:01:18.710887Z   WARN - Packet bytes (141 bytes)
    hex_data = "2b00000bfa0003136d696e6563726166743a6f766572776f726c64116d696e6563726166743a7468655f656e64146d696e6563726166743a7468655f6e6574686572140a0a00010000136d696e6563726166743a6f766572776f726c64c2cbb3304082e5ad00ff000101136d696e6563726166743a6f766572776f726c640000000000000fed00c1ffffff0f00"
    
    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes
    
    puts "JoinGame packet serialization test"
    puts "Original packet size: #{original_bytes.size} bytes"
    puts "Original bytes (first 32): #{original_bytes[0..31].hexstring}"
    
    # Parse the packet - skip packet ID (first byte is 0x2B)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::JoinGame.read(io)
    
    puts "Parsed packet:"
    puts "  Entity ID: #{packet.entity_id}"
    puts "  Hardcore: #{packet.hardcore?}"
    puts "  Dimension names: #{packet.dimension_names}"
    puts "  Max players: #{packet.max_players}"
    puts "  View distance: #{packet.view_distance}"
    puts "  Simulation distance: #{packet.simulation_distance}"
    puts "  Reduced debug info: #{packet.reduced_debug_info?}"
    puts "  Enable respawn screen: #{packet.enable_respawn_screen?}"
    puts "  Do limited crafting: #{packet.do_limited_crafting?}"
    puts "  Dimension type: #{packet.dimension_type}"
    puts "  Dimension name: #{packet.dimension_name}"
    puts "  Hashed seed: #{packet.hashed_seed}"
    puts "  Gamemode: #{packet.gamemode}"
    puts "  Previous gamemode: #{packet.previous_gamemode}"
    puts "  Is debug: #{packet.is_debug?}"
    puts "  Is flat: #{packet.is_flat?}"
    puts "  Has death location: #{packet.has_death_location?}"
    if packet.has_death_location?
      puts "  Death dimension name: #{packet.death_dimension_name}"
      puts "  Death location: #{packet.death_location}"
    end
    puts "  Portal cooldown: #{packet.portal_cooldown}"
    puts "  Sea level: #{packet.sea_level}"
    puts "  Enforces secure chat: #{packet.enforces_secure_chat?}"
    
    # Write the packet back out
    rewritten_bytes = packet.write
    
    puts "Rewritten packet size: #{rewritten_bytes.size} bytes"
    puts "Rewritten bytes (first 32): #{rewritten_bytes[0..31].hexstring}"
    
    # Compare the bytes - rewritten includes packet ID, so compare with original
    if original_bytes == rewritten_bytes
      puts "✅ Perfect match! Packet roundtrip successful."
      expect(rewritten_bytes).to eq(original_bytes)
    else
      puts "❌ Mismatch detected!"
      puts "Expected: #{original_bytes.hexstring}"
      puts "Got:      #{rewritten_bytes.hexstring}"
      
      # Find first difference
      min_size = [original_bytes.size, rewritten_bytes.size].min
      first_diff = nil
      (0...min_size).each do |i|
        if original_bytes[i] != rewritten_bytes[i]
          first_diff = i
          break
        end
      end
      
      if first_diff
        puts "First difference at byte #{first_diff}:"
        puts "  Original: 0x#{original_bytes[first_diff].to_s(16).upcase.rjust(2, '0')}"
        puts "  Rewritten: 0x#{rewritten_bytes[first_diff].to_s(16).upcase.rjust(2, '0')}"
      elsif original_bytes.size != rewritten_bytes.size
        puts "Size difference: original=#{original_bytes.size}, rewritten=#{rewritten_bytes.size}"
      end
      
      # This will fail the test
      expect(rewritten_bytes).to eq(original_bytes)
    end
  end
end