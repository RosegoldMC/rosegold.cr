require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::Punch do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses the 26.3 punch packet id" do
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x2E_u32)
  end

  it "writes only the packet id" do
    Rosegold::Client.protocol_version = 777_u32

    expect(described_class.new.write).to eq(Bytes[0x2E])
  end
end
