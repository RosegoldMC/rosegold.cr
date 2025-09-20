require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::Login do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::Login[772_u32]).to eq(0x2B_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::Login.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::Login.supports_protocol?(999_u32)).to be_false
  end
end
