require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::JoinGame do
  it "uses correct packet IDs for different protocol versions" do
    expect(Rosegold::Clientbound::JoinGame[758_u32]).to eq(0x26_u8)
    expect(Rosegold::Clientbound::JoinGame[767_u32]).to eq(0x29_u8)
    expect(Rosegold::Clientbound::JoinGame[771_u32]).to eq(0x29_u8)
  end

  it "supports all defined protocols" do
    expect(Rosegold::Clientbound::JoinGame.supports_protocol?(758_u32)).to be_true
    expect(Rosegold::Clientbound::JoinGame.supports_protocol?(767_u32)).to be_true
    expect(Rosegold::Clientbound::JoinGame.supports_protocol?(771_u32)).to be_true
    expect(Rosegold::Clientbound::JoinGame.supports_protocol?(999_u32)).to be_false
  end
end
