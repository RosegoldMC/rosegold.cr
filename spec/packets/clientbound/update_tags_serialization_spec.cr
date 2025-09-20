require "../../spec_helper"

Spectator.describe "UpdateTags Serialization" do
  it "can create, write, and read UpdateTags packet with basic data" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Create test tag data
    test_tags = [
      {
        type: "minecraft:block",
        tags: [
          {
            name:    "minecraft:logs",
            entries: [1_u32, 2_u32, 3_u32], # Block IDs for logs
          },
          {
            name:    "minecraft:planks",
            entries: [4_u32, 5_u32, 6_u32], # Block IDs for planks
          },
        ],
      },
      {
        type: "minecraft:item",
        tags: [
          {
            name:    "minecraft:tools",
            entries: [10_u32, 11_u32, 12_u32], # Item IDs for tools
          },
        ],
      },
    ]

    # Create UpdateTags packet
    packet = Rosegold::Clientbound::UpdateTags.new(test_tags)

    # Write the packet
    written_bytes = packet.write

    # Read it back - skip packet ID (first byte)
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::UpdateTags.read(io)

    # Verify the data matches
    expect(parsed_packet.tag_types.size).to eq(test_tags.size)
    expect(parsed_packet.tag_types[0][:type]).to eq("minecraft:block")
    expect(parsed_packet.tag_types[0][:tags].size).to eq(2)
    expect(parsed_packet.tag_types[0][:tags][0][:name]).to eq("minecraft:logs")
    expect(parsed_packet.tag_types[0][:tags][0][:entries]).to eq([1_u32, 2_u32, 3_u32])

    expect(parsed_packet.tag_types[1][:type]).to eq("minecraft:item")
    expect(parsed_packet.tag_types[1][:tags].size).to eq(1)
    expect(parsed_packet.tag_types[1][:tags][0][:name]).to eq("minecraft:tools")
    expect(parsed_packet.tag_types[1][:tags][0][:entries]).to eq([10_u32, 11_u32, 12_u32])

    # Write the parsed packet back and compare
    rewritten_bytes = parsed_packet.write

    expect(rewritten_bytes).to eq(written_bytes)
  end

  it "can handle empty UpdateTags packet" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Create empty UpdateTags packet
    empty_packet = Rosegold::Clientbound::UpdateTags.new

    # Write and read back
    written_bytes = empty_packet.write
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::UpdateTags.read(io)

    # Verify
    expect(parsed_packet.tag_types.size).to eq(0)
    expect(parsed_packet.write).to eq(written_bytes)
  end
end
