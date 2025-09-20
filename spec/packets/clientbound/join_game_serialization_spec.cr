require "../../spec_helper"

Spectator.describe "Login Serialization" do
  it "can read and write Login packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Captured Login packet data from log
    # 2025-08-05T00:01:18.710887Z   WARN - Packet bytes (141 bytes)
    hex_data = "2b00000bfa0003136d696e6563726166743a6f766572776f726c64116d696e6563726166743a7468655f656e64146d696e6563726166743a7468655f6e6574686572140a0a00010000136d696e6563726166743a6f766572776f726c64c2cbb3304082e5ad00ff000101136d696e6563726166743a6f766572776f726c640000000000000fed00c1ffffff0f00"

    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte is 0x2B)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::Login.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes - rewritten includes packet ID, so compare with original
    expect(rewritten_bytes).to eq(original_bytes)
  end
end
