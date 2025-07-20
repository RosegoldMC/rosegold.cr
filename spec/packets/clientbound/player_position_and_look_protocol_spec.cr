require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::PlayerPositionAndLook do
  it "uses correct packet IDs for different protocol versions" do
    expect(Rosegold::Clientbound::PlayerPositionAndLook[758_u32]).to eq(0x38_u8)
    expect(Rosegold::Clientbound::PlayerPositionAndLook[767_u32]).to eq(0x3C_u8)
    expect(Rosegold::Clientbound::PlayerPositionAndLook[771_u32]).to eq(0x3C_u8)
  end

  it "supports all defined protocols" do
    expect(Rosegold::Clientbound::PlayerPositionAndLook.supports_protocol?(758_u32)).to be_true
    expect(Rosegold::Clientbound::PlayerPositionAndLook.supports_protocol?(767_u32)).to be_true
    expect(Rosegold::Clientbound::PlayerPositionAndLook.supports_protocol?(771_u32)).to be_true
    expect(Rosegold::Clientbound::PlayerPositionAndLook.supports_protocol?(999_u32)).to be_false
  end
end
