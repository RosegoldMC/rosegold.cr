require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::WindowItems do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/window_items.mcpacket", __FILE__) }

  it "works" do
    # read the packet
    packet = Rosegold::Clientbound::WindowItems.read(io)

    # check the packet
    expect(packet.window_id).to eq(0)
    # expect(packet.slots).to be_a(Array)
    # expect(packet.slots.length).to eq(46)
    # expect(packet.slots[0]).to be_a(Rosegold::Slot)
    # expect(packet.slots[0].item_id).to eq(0)
    # expect(packet.slots[0].item_count).to eq(0)
    # expect(packet.slots[0].item_nbt).to be_nil
  end
end
