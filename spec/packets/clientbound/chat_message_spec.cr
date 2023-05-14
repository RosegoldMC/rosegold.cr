require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::ChatMessage do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/chat_message.mcpacket", __FILE__) }

  it "works" do
    # read the packet
    packet = Rosegold::Clientbound::ChatMessage.read(io)
    chat = Rosegold::Chat.new("Connecting to the server...")
    chat.color = "gold"
    # check the packet
    expect(packet.message).to be_a(Rosegold::Chat)
    expect(packet.position).to be_a(UInt8)
    expect(packet.sender).to be_a(UUID)
    expect(packet.message.to_s).to eq(chat.to_s)
    expect(packet.position).to eq(0)
    expect(packet.sender).to eq(UUID.new("00000000-0000-0000-0000-000000000000"))
  end
end 
