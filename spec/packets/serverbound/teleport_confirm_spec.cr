require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::TeleportConfirm do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "writes the 26.3 acknowledgement pose after its teleport id" do
    Rosegold::Client.protocol_version = 777_u32

    packet = described_class.new(300_u32, 11.25, -2.5, 3.75, 135.0_f32, -30.0_f32)

    expect(packet.write).to eq(
      "00ac024026800000000000c004000000000000400e00000000000043070000c1f00000".hexbytes
    )
  end

  it "keeps the pre-26.3 acknowledgement wire format" do
    Rosegold::Client.protocol_version = 776_u32

    expect(described_class.new(300_u32, 11.25, -2.5, 3.75, 135.0_f32, -30.0_f32).write).to eq("00ac02".hexbytes)
  end

  it "consumes the full 26.3 acknowledgement from a spectator" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "ac024026800000000000c004000000000000400e00000000000043070000c1f00000".hexbytes
    io = Minecraft::IO::Memory.new(bytes)
    packet = described_class.read(io)

    expect(io.pos).to eq(bytes.size)
    expect(packet.teleport_id).to eq(300_u32)
    expect(packet.x).to eq(11.25)
    expect(packet.yaw).to eq(135_f32)
  end
end
