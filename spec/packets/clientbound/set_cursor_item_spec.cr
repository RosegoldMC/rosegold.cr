require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetCursorItem do
  it "uses correct packet IDs per protocol" do
    expect(Rosegold::Clientbound::SetCursorItem[772_u32]).to eq(0x59_u32)
    expect(Rosegold::Clientbound::SetCursorItem[774_u32]).to eq(0x5E_u32)
    expect(Rosegold::Clientbound::SetCursorItem[775_u32]).to eq(0x60_u32)
  end

  describe "parsing" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    it "reads an empty carried item (count=0)" do
      io = Minecraft::IO::Memory.new(Bytes[0x00])
      packet = Rosegold::Clientbound::SetCursorItem.read(io)
      expect(packet.carried_item.empty?).to be_true
    end

    it "reads a non-empty carried item" do
      slot = Rosegold::Slot.new(count: 3_u32, item_id_int: 42_u32)
      out = Minecraft::IO::Memory.new
      out.write slot
      bytes = out.to_slice

      io = Minecraft::IO::Memory.new(bytes)
      packet = Rosegold::Clientbound::SetCursorItem.read(io)
      expect(packet.carried_item.empty?).to be_false
      expect(packet.carried_item.count).to eq(3_u32)
      expect(packet.carried_item.item_id_int).to eq(42_u32)
    end

    it "round-trips through write()" do
      slot = Rosegold::Slot.new(count: 7_u32, item_id_int: 100_u32)
      packet = Rosegold::Clientbound::SetCursorItem.new(slot)

      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)
      io.read_byte # packet id
      reparsed = Rosegold::Clientbound::SetCursorItem.read(io)

      expect(reparsed.carried_item.count).to eq(7_u32)
      expect(reparsed.carried_item.item_id_int).to eq(100_u32)
    end
  end

  describe "callback" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    let(:client) do
      Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "cursortest"})
    end

    # Reproduces the JukeAlert/Bukkit-cancel scenario: bot optimistically picks
    # up an item; the server then sends SetCursorItem(empty) to revert. Prior
    # to the SetCursorItem handler, the bot's @cursor stayed populated and the
    # snitch_extraction.cr workaround had to clear it manually.
    it "clears the menu cursor when the server reverts to empty" do
      menu = client.container_menu
      menu.cursor = Rosegold::Slot.new(count: 1_u32, item_id_int: 42_u32)

      packet = Rosegold::Clientbound::SetCursorItem.new(Rosegold::Slot.new)
      packet.callback(client)

      expect(menu.cursor.empty?).to be_true
    end

    it "syncs both local and remote cursor so desync detection won't fire" do
      menu = client.container_menu
      menu.cursor = Rosegold::Slot.new(count: 1_u32, item_id_int: 42_u32)

      packet = Rosegold::Clientbound::SetCursorItem.new(Rosegold::Slot.new(count: 5_u32, item_id_int: 99_u32))
      packet.callback(client)

      expect(menu.cursor.item_id_int).to eq(99_u32)
      expect(menu.cursor.count).to eq(5_u32)
      # Desync check would request resync if remote_cursor diverges; the
      # authoritative cursor packet must update both.
      expect { menu.check_and_fix_desync }.not_to raise_error
    end
  end
end
