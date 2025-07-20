# Clientbound Packet Serialization Specs

This directory contains 2-way serialization specs for clientbound (incoming) packets. These specs test that packets can be properly read from binary data and then written back to identical binary data, ensuring that our packet parsing and serialization is complete and correct.

## How It Works

Each spec follows this pattern:

1. **Parsing Test**: Reads a packet from a fixture file and verifies the parsed data has the correct types and values
2. **Serialization Test**: Reads a packet from the fixture file, then writes it back and compares the output to the original fixture data

```crystal
it "writes packet the same after parsing" do
  io.read_byte  # Skip packet ID byte

  expect(Rosegold::Clientbound::PacketClass.read(io).write).to eq file_slice
end
```

## Current Status

| Packet | Fixture | Spec | Status |
|--------|---------|------|--------|
| ChatMessage | ✅ | ✅ | ✅ Working |
| ChunkData | ✅ | ✅ | ✅ Working |
| LoginSuccess | ✅ | ✅ | ✅ Working |
| PlayerPositionAndLook | ✅ | ✅ | ✅ Working |
| WindowItems | ✅ | ✅ | ⚠️ Version mismatch (skipped) |

## Version Compatibility Issues

Some fixture files may have been captured with different Minecraft versions, leading to packet ID mismatches:

- **WindowItems**: Fixture has packet ID `0x00` but current class expects `0x14`

## Adding New Packet Specs

To add a spec for a new packet:

1. **Capture a packet fixture** (see [wiki](https://github.com/RosegoldMC/rosegold.cr/wiki/How-to-capture-packet-for-fixtures))
2. **Create a spec file** following the existing pattern:

```crystal
require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::YourPacket do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/your_packet.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  it "parses the packet" do
    io.read_byte
    packet = Rosegold::Clientbound::YourPacket.read(io)

    # Type assertions
    expect(packet.field).to be_a(ExpectedType)
    
    # Value assertions (if known)
    expect(packet.field).to eq(expected_value)
  end

  it "writes packet the same after parsing" do
    io.read_byte

    expect(Rosegold::Clientbound::YourPacket.read(io).write).to eq file_slice
  end
end
```

3. **Verify packet ID compatibility** between the fixture file and the packet class

## Benefits

These tests prove that:
- We parse all packet data correctly (otherwise we couldn't write it back)
- Our serialization is complete and accurate
- Packet definitions match the actual protocol