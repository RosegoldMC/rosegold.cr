require "../spec_helper"

private class ContainerCloseSpecClient < Rosegold::Client
  getter closed_windows = [] of UInt16
  property during_close_write : Proc(Nil)?

  def send_packet_if!(packet : GuardedPacket, session : PlaySession? = nil, &guard : -> Bool) : Bool
    return false unless packet.is_a?(Rosegold::Serverbound::CloseWindow) && guard.call
    @closed_windows << packet.window_id
    during_close_write.try &.call
    true
  end
end

Spectator.describe Rosegold::ContainerMenu do
  it "preserves a replacement with the same ID that opens during the close write" do
    client = ContainerCloseSpecClient.new("localhost")
    title = Rosegold::Chat.new("Chest")
    menu = Rosegold::ChestMenu.new(client, 1_u8, title, 1)
    client.container_menu = menu
    replacement = Rosegold::Clientbound::OpenWindow.new(1_u32, 0_u32, title)
    client.during_close_write = -> { replacement.callback(client); nil }
    closed = [] of UInt32
    client.on(Rosegold::Event::ContainerClosed) { |event| closed << event.window_id }

    menu.close

    expect(client.closed_windows).to eq([1_u16])
    expect(client.container_menu.id).to eq(1_u8)
    expect(client.container_menu.same?(menu)).to be_false
    expect(closed).to be_empty
  end

  it "does not send a close for a stale menu with the same ID as the current menu" do
    client = ContainerCloseSpecClient.new("localhost")
    title = Rosegold::Chat.new("Chest")
    menu = Rosegold::ChestMenu.new(client, 1_u8, title, 1)
    replacement = Rosegold::ChestMenu.new(client, 1_u8, title, 1)
    client.container_menu = replacement

    menu.close

    expect(client.closed_windows).to be_empty
    expect(client.container_menu.same?(replacement)).to be_true
  end

  it "preserves a replacement opened by a close listener" do
    client = ContainerCloseSpecClient.new("localhost")
    title = Rosegold::Chat.new("Chest")
    menu = Rosegold::ChestMenu.new(client, 1_u8, title, 1)
    replacement = Rosegold::ChestMenu.new(client, 1_u8, title, 1)
    client.container_menu = menu
    closed = [] of UInt32
    client.on Rosegold::Event::ContainerClosed do |event|
      closed << event.window_id
      client.container_menu = replacement
    end

    menu.close

    expect(client.closed_windows).to eq([1_u16])
    expect(closed).to eq([1_u32])
    expect(client.container_menu.same?(replacement)).to be_true
  end
end
