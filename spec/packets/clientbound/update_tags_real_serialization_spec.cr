require "../../spec_helper"

Spectator.describe "UpdateTags Real Packet Serialization" do
  it "can read and write real UpdateTags packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Read the real UpdateTags packet from file
    hex_data = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/update_tags.hex")).strip

    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte is 0x0D)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::UpdateTags.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes
    expect(rewritten_bytes).to eq(original_bytes)
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
    tag_type_names = packet.tag_types.map { |tag_type| tag_type[:type] }
    expect(tag_type_names).to contain("minecraft:fluid")

    # Check the fluid tag type specifically if it exists
    fluid_tag_type = packet.tag_types.find { |tag_type| tag_type[:type] == "minecraft:fluid" }
    if fluid_tag_type
      # Check that we have some expected fluid tags
      tag_names = fluid_tag_type[:tags].map { |tag| tag[:name] }
      expect(tag_names).to contain("minecraft:lava")
      expect(tag_names).to contain("minecraft:water")
    end
  end
end
