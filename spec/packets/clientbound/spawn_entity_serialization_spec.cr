require "../../spec_helper"

Spectator.describe "SpawnEntity Serialization (Protocol 774)" do
  let(hex_data) { "01f2a060808df746159f476186d76c8ff8cb27d7344095813269560000400c00000000000040b367fd21780000c9038ca6fca200fc00e958" }

  after_each { Rosegold::Client.reset_protocol_version! }

  it "can parse all fields correctly from captured 1.21.11 packet" do
    Rosegold::Client.protocol_version = 774_u32

    # Captured SpawnEntity packet data from live 1.21.11 server
    # 2026-03-14T14:45:16.331098Z   WARN - Packet bytes (56 bytes)
    original_bytes = hex_data.hexbytes
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SpawnEntity.read(io)

    expect(packet.entity_id).to eq(1577074_u32)
    expect(packet.uuid).to eq(UUID.new("808df746-159f-4761-86d7-6c8ff8cb27d7"))
    expect(packet.entity_type).to eq(52_u32)
    expect(packet.x).to be_close(1376.2992299497128, 1e-6)
    expect(packet.y).to eq(3.5)
    expect(packet.z).to be_close(4967.988791942596, 1e-6)
    expect(packet.pitch).to be_close(0.0, 1e-3)
    expect(packet.yaw).to be_close(354.375, 1e-3)
    expect(packet.head_yaw).to be_close(0.0, 1e-3)
    expect(packet.data).to eq(11369_u32)
  end

  it "round-trips with byte-perfect equality" do
    Rosegold::Client.protocol_version = 774_u32

    original_bytes = hex_data.hexbytes
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SpawnEntity.read(io)
    rewritten_bytes = packet.write

    expect(rewritten_bytes).to eq(original_bytes)
  end
end
