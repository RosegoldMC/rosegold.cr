require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::SelectTrade do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Serverbound::SelectTrade[772_u32]).to eq(0x32_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Serverbound::SelectTrade[773_u32]).to eq(0x32_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Serverbound::SelectTrade[774_u32]).to eq(0x32_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Serverbound::SelectTrade[775_u32]).to eq(0x33_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Serverbound::SelectTrade[776_u32]).to eq(0x33_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Serverbound::SelectTrade.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Serverbound::SelectTrade.supports_protocol?(999_u32)).to be_false
  end

  describe "round-trip serialization" do
    it "writes the selected trade index as a VarInt after the packet id" do
      Rosegold::Client.protocol_version = 772_u32

      io = Minecraft::IO::Memory.new(Rosegold::Serverbound::SelectTrade.new(3).write)

      expect(io.read_byte).to eq(0x32_u8)
      expect(io.read_var_int).to eq(3_u32)
    end

    it "uses the shifted 0x33 id on protocol 775" do
      Rosegold::Client.protocol_version = 775_u32

      io = Minecraft::IO::Memory.new(Rosegold::Serverbound::SelectTrade.new(1).write)

      expect(io.read_byte).to eq(0x33_u8)
      expect(io.read_var_int).to eq(1_u32)
    end
  end
end
