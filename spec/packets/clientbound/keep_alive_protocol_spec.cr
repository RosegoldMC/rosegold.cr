require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::KeepAlive do
  it "uses correct packet IDs for different protocol versions" do
    expect(Rosegold::Clientbound::KeepAlive[758_u32]).to eq(0x21_u8)
    expect(Rosegold::Clientbound::KeepAlive[767_u32]).to eq(0x24_u8)
    expect(Rosegold::Clientbound::KeepAlive[771_u32]).to eq(0x24_u8)
  end

  it "supports all defined protocols" do
    expect(Rosegold::Clientbound::KeepAlive.supports_protocol?(758_u32)).to be_true
    expect(Rosegold::Clientbound::KeepAlive.supports_protocol?(767_u32)).to be_true
    expect(Rosegold::Clientbound::KeepAlive.supports_protocol?(771_u32)).to be_true
    expect(Rosegold::Clientbound::KeepAlive.supports_protocol?(999_u32)).to be_false
  end
end