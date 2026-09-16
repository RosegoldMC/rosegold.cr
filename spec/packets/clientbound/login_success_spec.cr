require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::LoginSuccess do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips the 26.2 login fixture with its session id" do
    Rosegold::Client.protocol_version = 776_u32

    original_bytes = "0212345678901234567890123456789012047465737400aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".hexbytes
    packet = described_class.read(Minecraft::IO::Memory.new(original_bytes[1..]))

    expect(packet.session_id).to eq(UUID.new("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    expect(packet.write).to eq(original_bytes)
  end

  it "uses the same login packet id for 26.3" do
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x02_u32)
  end
end
