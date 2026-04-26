require "../../spec_helper"

Spectator.describe "UnloadChunk Serialization" do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "roundtrips positive coordinates" do
    Rosegold::Client.protocol_version = 774_u32

    original = Rosegold::Clientbound::UnloadChunk.new(
      chunk_x: 10_i32,
      chunk_z: 15_i32
    )

    io = Minecraft::IO::Memory.new(original.write)
    io.read_var_int
    deserialized = Rosegold::Clientbound::UnloadChunk.read(io)

    expect(deserialized.chunk_x).to eq(10_i32)
    expect(deserialized.chunk_z).to eq(15_i32)
  end

  it "roundtrips negative coordinates without overflow" do
    Rosegold::Client.protocol_version = 774_u32

    original = Rosegold::Clientbound::UnloadChunk.new(
      chunk_x: -176_i32,
      chunk_z: -159_i32
    )

    serialized = original.write
    io = Minecraft::IO::Memory.new(serialized)
    io.read_var_int
    deserialized = Rosegold::Clientbound::UnloadChunk.read(io)

    expect(deserialized.chunk_x).to eq(-176_i32)
    expect(deserialized.chunk_z).to eq(-159_i32)
    expect(deserialized.write).to eq(serialized)
  end

  it "parses the problematic packet bytes from logs" do
    Rosegold::Client.protocol_version = 774_u32

    # Captured wire bytes that previously raised OverflowError on read
    bytes = Bytes[0x25, 0xff, 0xff, 0xff, 0x61, 0xff, 0xff, 0xff, 0x50]

    io = Minecraft::IO::Memory.new(bytes)
    expect(io.read_var_int).to eq(0x25_u32)

    packet = Rosegold::Clientbound::UnloadChunk.read(io)
    expect(packet.chunk_x).to eq(-176_i32)
    expect(packet.chunk_z).to eq(-159_i32)

    expect(packet.write).to eq(bytes)
  end
end
