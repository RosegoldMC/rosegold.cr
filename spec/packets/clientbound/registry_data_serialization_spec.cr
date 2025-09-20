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

    # Parse the packet - skip packet ID (first byte is 0x07)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::RegistryData.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes - rewritten includes packet ID, so compare with original
    expect(rewritten_bytes).to eq(original_bytes)
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
  end
end
