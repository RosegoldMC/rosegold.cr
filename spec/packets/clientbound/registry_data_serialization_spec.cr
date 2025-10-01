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

  it "can parse chat_type registry with NBT data entries" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Captured from log: Failed to parse RegistryData (0x07) - 356 bytes
    hex_data = "07136d696e6563726166743a636861745f74797065080e6d696e6563726166743a6368617400176d696e6563726166743a656d6f74655f636f6d6d616e64001e6d696e6563726166743a6d73675f636f6d6d616e645f696e636f6d696e67001e6d696e6563726166743a6d73675f636f6d6d616e645f6f7574676f696e67000970617065723a726177010a0a00046368617408000f7472616e736c6174696f6e5f6b65790002257309000a706172616d657465727308000000010007636f6e74656e74000a00096e6172726174696f6e08000f7472616e736c6174696f6e5f6b65790002257309000a706172616d657465727308000000010007636f6e74656e740000156d696e6563726166743a7361795f636f6d6d616e6400236d696e6563726166743a7465616d5f6d73675f636f6d6d616e645f696e636f6d696e6700236d696e6563726166743a7465616d5f6d73675f636f6d6d616e645f6f7574676f696e6700"
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte is 0x07)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::RegistryData.read(io)

    # Write the packet back out and verify size match
    rewritten_bytes = packet.write
    expect(rewritten_bytes.size).to eq(original_bytes.size)

    # Test round-trip parsing
    io2 = Minecraft::IO::Memory.new(rewritten_bytes[1..])
    reparsed_packet = Rosegold::Clientbound::RegistryData.read(io2)

    expect(reparsed_packet.registry_id).to eq(packet.registry_id)
    expect(reparsed_packet.entries.size).to eq(packet.entries.size)

    # Verify all entries match
    reparsed_packet.entries.zip(packet.entries) do |reparsed, original|
      expect(reparsed[:id]).to eq(original[:id])
      expect(reparsed[:data]).to eq(original[:data])
    end
  end
end
