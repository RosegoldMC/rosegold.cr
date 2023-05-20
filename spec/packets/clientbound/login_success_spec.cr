require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::LoginSuccess do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/login_success.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  it "parses the packet" do
    io.read_byte
    packet = Rosegold::Clientbound::LoginSuccess.read(io)

    expect(packet.uuid).to be_a(UUID)
    expect(packet.username).to be_a(String)

    expect(packet.uuid).to eq(UUID.new("23206230-679e-4c49-93c2-9828a0921f2a"))
    expect(packet.username).to eq("Drekamor")
  end

  it "writes packet the same after parsing" do
    io.read_byte

    expect(Rosegold::Clientbound::LoginSuccess.read(io).write).to eq file_slice
  end
end
