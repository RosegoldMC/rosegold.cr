require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::ChatMessage do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/chat_message.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  # Set protocol to 758 to match the fixture file
  before_each do
    Rosegold::Client.protocol_version = 758_u32
  end

  after_each do
    # Reset to default 
    Rosegold::Client.protocol_version = 771_u32
  end

  it "parses the packet" do
    io.read_byte
    packet = Rosegold::Clientbound::ChatMessage.read(io)
    chat = Rosegold::Chat.new("[!] Drekamor: Hello Rosegold World!")
    expect(packet.message).to be_a(Rosegold::Chat)
    expect(packet.position).to be_a(UInt8)
    expect(packet.sender).to be_a(UUID)
    expect(packet.message.to_s).to eq(chat.to_s)
    expect(packet.position).to eq(1)
    expect(packet.sender).to eq(UUID.new("00000000-0000-0000-0000-000000000000"))
  end

  it "writes packet the same after parsing" do
    io.read_byte

    expect(Rosegold::Clientbound::ChatMessage.read(io).write).to eq file_slice
  end

  it "uses correct packet IDs for different protocol versions" do
    expect(Rosegold::Clientbound::ChatMessage[758_u32]).to eq(0x0F_u8)
    expect(Rosegold::Clientbound::ChatMessage[767_u32]).to eq(0x68_u8)
    expect(Rosegold::Clientbound::ChatMessage[771_u32]).to eq(0x68_u8)
  end
end
