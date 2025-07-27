require "./spec_helper"

Spectator.describe "JoinGame packet roundtrip" do
  it "can read and write captured JoinGame packet identically" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Read the captured real packet (using Int32 entity_id format)
    packet_bytes = File.read("spec/fixtures/packets/clientbound/join_game_int32.bin").to_slice
    puts "Original packet size: #{packet_bytes.size} bytes"
    puts "Original bytes: #{packet_bytes[0, [32, packet_bytes.size].min].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

    # Parse the packet - skip packet ID
    io = Minecraft::IO::Memory.new(packet_bytes[1..])
    join_game = Rosegold::Clientbound::JoinGame.read(io)

    puts "Parsed packet:"
    puts "  Entity ID: #{join_game.entity_id}"
    puts "  Hardcore: #{join_game.hardcore?}"
    puts "  Dimensions: #{join_game.dimension_names}"
    puts "  Max players: #{join_game.max_players}"
    puts "  View distance: #{join_game.view_distance}"
    puts "  Dimension type: #{join_game.dimension_type}"
    puts "  Dimension name: #{join_game.dimension_name}"
    puts "  Gamemode: #{join_game.gamemode}"

    # Re-serialize the packet
    rewritten_bytes = join_game.write
    puts "Rewritten packet size: #{rewritten_bytes.size} bytes"
    puts "Rewritten bytes: #{rewritten_bytes[0, [32, rewritten_bytes.size].min].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

    # Compare
    if packet_bytes == rewritten_bytes
      puts "✅ Perfect match! Packet roundtrip successful."
    else
      puts "❌ Mismatch detected!"
      puts "Original:  #{packet_bytes.size} bytes"
      puts "Rewritten: #{rewritten_bytes.size} bytes"

      # Show differences
      min_size = [packet_bytes.size, rewritten_bytes.size].min
      (0...min_size).each do |i|
        if packet_bytes[i] != rewritten_bytes[i]
          puts "Diff at byte #{i}: original=0x#{packet_bytes[i].to_s(16).upcase.rjust(2, '0')} rewritten=0x#{rewritten_bytes[i].to_s(16).upcase.rjust(2, '0')}"
        end
      end
    end

    # The test assertion
    expect(rewritten_bytes).to eq packet_bytes
  end
end
