require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::ContainerButtonClick do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses the vanilla packet id for every enabled protocol" do
    Rosegold::ENABLED_PROTOCOLS.each_key do |protocol|
      protocol = protocol.to_u32
      expected = protocol <= 774_u32 ? 0x10_u32 : 0x11_u32
      expect(Rosegold::Serverbound::ContainerButtonClick[protocol]).to eq(expected)
      expect(Rosegold::Serverbound::ContainerButtonClick.supports_protocol?(protocol)).to be_true
    end
  end

  it "does not claim support for an unknown protocol" do
    expect(Rosegold::Serverbound::ContainerButtonClick.supports_protocol?(999_u32)).to be_false
  end

  it "serializes both ids as VarInts, including a multi-byte container id" do
    Rosegold::Client.protocol_version = 777_u32

    bytes = Rosegold::Serverbound::ContainerButtonClick.new(300_u32, 2).write
    io = Minecraft::IO::Memory.new(bytes)

    expect(io.read_var_int).to eq(0x11_u32)
    expect(io.read_var_int).to eq(300_u32)
    expect(io.read_var_int).to eq(2_u32)
    expect(io.pos).to eq(io.size)
  end

  it "uses the pre-26.1 id while retaining VarInt fields" do
    Rosegold::Client.protocol_version = 772_u32

    io = Minecraft::IO::Memory.new(Rosegold::Serverbound::ContainerButtonClick.new(128_u32, 0).write)

    expect(io.read_var_int).to eq(0x10_u32)
    expect(io.read_var_int).to eq(128_u32)
    expect(io.read_var_int).to eq(0_u32)
  end
end
