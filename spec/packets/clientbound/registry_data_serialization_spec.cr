require "../../spec_helper"

Spectator.describe "RegistryData Serialization" do
  it "can read and write RegistryData packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32
    
    # Captured RegistryData packet data from log
    # 2025-08-05T01:06:44.852752Z   WARN - Packet bytes (116 bytes)
    # registry_id => minecraft:dimension_type
    hex_data = "07186d696e6563726166743a64696d656e73696f6e5f7479706504136d696e6563726166743a6f766572776f726c6400196d696e6563726166743a6f766572776f726c645f636176657300116d696e6563726166743a7468655f656e6400146d696e6563726166743a7468655f6e657468657200"
    
    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes
    
    puts "RegistryData packet serialization test"
    puts "Original packet size: #{original_bytes.size} bytes"
    puts "Original bytes (first 32): #{original_bytes[0..31].hexstring}"
    
    # Parse the packet - skip packet ID (first byte is 0x07)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::RegistryData.read(io)
    
    puts "Parsed packet:"
    puts "  Registry ID: #{packet.registry_id}"
    puts "  Entry count: #{packet.entries.size}"
    packet.entries.each_with_index do |entry, index|
      puts "  Entry #{index}: id='#{entry[:id]}', has_data=#{!entry[:data].nil?}"
      if data = entry[:data]
        puts "    Data: #{data.size} bytes - #{data[0..15].hexstring}#{data.size > 16 ? "..." : ""}"
      end
    end
    
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
        
        # Show context around the difference
        start_ctx = [0, first_diff - 5].max
        end_ctx = [min_size - 1, first_diff + 5].min
        puts "  Context - Original:  #{original_bytes[start_ctx..end_ctx].hexstring}"
        puts "  Context - Rewritten: #{rewritten_bytes[start_ctx..end_ctx].hexstring}"
      elsif original_bytes.size != rewritten_bytes.size
        puts "Size difference: original=#{original_bytes.size}, rewritten=#{rewritten_bytes.size}"
      end
      
      # This will fail the test
      expect(rewritten_bytes).to eq(original_bytes)
    end
  end
  
  it "can parse dimension_type registry entries correctly" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32
    
    # Same packet data as above test
    hex_data = "07186d696e6563726166743a64696d656e73696f6e5f7479706504136d696e6563726166743a6f766572776f726c6400196d696e6563726166743a6f766572776f726c645f636176657300116d696e6563726166743a7468655f656e6400146d696e6563726166743a7468655f6e657468657200"
    original_bytes = hex_data.hexbytes
    
    # Parse the packet
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::RegistryData.read(io)
    
    # Validate the specific registry content
    expect(packet.registry_id).to eq("minecraft:dimension_type")
    expect(packet.entries.size).to eq(4)
    
    # Check that we have the expected dimension types
    entry_ids = packet.entries.map { |entry| entry[:id] }
    expect(entry_ids).to contain("minecraft:overworld")
    expect(entry_ids).to contain("minecraft:overworld_caves")
    expect(entry_ids).to contain("minecraft:the_end")
    expect(entry_ids).to contain("minecraft:the_nether")
    
    # All dimension_type entries should have no data (NBT data is separate)
    packet.entries.each do |entry|
      expect(entry[:data]).to be_nil
    end
    
    puts "✅ RegistryData dimension_type entries validated successfully"
  end
end