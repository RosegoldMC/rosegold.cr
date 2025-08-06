require "../../spec_helper"

Spectator.describe "UpdateTags Real Packet Serialization" do
  it "can read and write real UpdateTags packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32
    
    # Read the real UpdateTags packet from file
    hex_data = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/update_tags.hex")).strip
    
    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes
    
    puts "UpdateTags real packet serialization test"
    puts "Original packet size: #{original_bytes.size} bytes"
    puts "Packet ID: 0x#{original_bytes[0].to_s(16).upcase.rjust(2, '0')}"
    puts "Original bytes (first 64): #{original_bytes[0..63].hexstring}"
    
    # Parse the packet - skip packet ID (first byte is 0x0D)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::UpdateTags.read(io)
    
    puts "Parsed packet:"
    puts "  Tag types: #{packet.tag_types.size}"
    packet.tag_types.each_with_index do |tag_type, i|
      puts "  Type #{i}: #{tag_type[:type]} (#{tag_type[:tags].size} tags)"
      if i < 3 # Show details for first few types
        tag_type[:tags].each_with_index do |tag, j|
          puts "    Tag #{j}: #{tag[:name]} (#{tag[:entries].size} entries)"
          if j < 2 && tag[:entries].size > 0 # Show entries for first few tags
            entries_preview = tag[:entries][0..4].map(&.to_s).join(", ")
            entries_preview += "..." if tag[:entries].size > 5
            puts "      Entries: [#{entries_preview}]"
          end
        end
      end
    end
    
    # Write the packet back out
    rewritten_bytes = packet.write
    
    puts "Rewritten packet size: #{rewritten_bytes.size} bytes"
    puts "Rewritten bytes (first 64): #{rewritten_bytes[0..63].hexstring}"
    
    # Compare the bytes
    if original_bytes == rewritten_bytes
      puts "✅ Perfect match! UpdateTags real packet roundtrip successful."
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
      
      # This will fail the test if there's a mismatch
      expect(rewritten_bytes).to eq(original_bytes)
    end
  end
  
  it "can parse minecraft:fluid tags correctly" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32
    
    # Read the same packet data from file
    hex_data = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/update_tags.hex")).strip
    original_bytes = hex_data.hexbytes
    
    # Parse the packet
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::UpdateTags.read(io)
    
    # Validate the packet was parsed successfully
    expect(packet.tag_types.size).to be > 0
    
    # Check that we have the expected tag types
    tag_type_names = packet.tag_types.map { |t| t[:type] }
    expect(tag_type_names).to contain("minecraft:fluid")
    
    # Check the fluid tag type specifically if it exists
    fluid_tag_type = packet.tag_types.find { |t| t[:type] == "minecraft:fluid" }
    if fluid_tag_type
      puts "Found minecraft:fluid tag type with #{fluid_tag_type[:tags].size} tags"
      
      # Check that we have some expected fluid tags
      tag_names = fluid_tag_type[:tags].map { |tag| tag[:name] }
      expect(tag_names).to contain("minecraft:lava")
      expect(tag_names).to contain("minecraft:water")
      
      puts "✅ Found expected minecraft:lava and minecraft:water tags"
    end
    
    puts "✅ UpdateTags minecraft:fluid tags validated successfully"
  end
end