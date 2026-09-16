require "./spec_helper"

class HandSwapSpecClient < Rosegold::Client
  def connection_for_test=(connection : Rosegold::Connection::Client)
    @connection = connection
  end
end

Spectator.describe "Rosegold::Bot#swap_hands" do
  def play_bot
    io = Minecraft::IO::Memory.new
    connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::PLAY, Rosegold::Client.protocol_version)
    client = HandSwapSpecClient.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "test"})
    client.connection_for_test = connection
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    {Rosegold::Bot.new(client), client, connection, io}
  end

  def deliver(client, packet)
    packet.callback(client)
    client.emit_event(packet)
  end

  def slot_update(window_id : Int8, index : Int32, slot : Rosegold::Slot)
    Rosegold::Clientbound::SetSlot.new(window_id, 1_u32, Rosegold::WindowSlot.new(index, slot))
  end

  def content_update(window_id : UInt32, slots : Array(Rosegold::Slot))
    Rosegold::Clientbound::SetContainerContent.new(window_id, 1_u32,
      slots.map_with_index { |slot, index| Rosegold::WindowSlot.new(index, slot) },
      Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
  end

  def swapped_slots(main, offhand)
    slots = Array.new(46) { Rosegold::Slot.new }
    slots[36] = main
    slots[45] = offhand
    slots
  end

  def damaged_slot(item_id : UInt32, damage : UInt32)
    components = Hash(String, Rosegold::DataComponent){"damage" => Rosegold::DataComponents::Damage.new(damage)}
    Rosegold::Slot.new(1_u32, item_id, components, Set(String).new)
  end

  it "sends the selected-slot synchronization before swap action and waits for both authoritative slot updates" do
    bot, client, _, io = play_bot
    main = Rosegold::Slot.new(1_u32, 1_u32)
    offhand = Rosegold::Slot.new(1_u32, 2_u32)
    client.player.hotbar_selection = 4_u32
    client.inventory_menu[40] = main
    client.inventory_menu[45] = offhand
    completed = false

    spawn do
      sleep 2.milliseconds
      deliver client, slot_update(0_i8, 45, main)
      sleep 2.milliseconds
      deliver client, slot_update(0_i8, 40, offhand)
      completed = true
    end

    bot.swap_hands(100.milliseconds)
    expect(completed).to be_true
    expect(client.inventory_menu[40].item_id_int).to eq(2_u32)
    expect(client.inventory_menu[45].item_id_int).to eq(1_u32)

    frame = Minecraft::IO::Memory.new(io.to_slice)
    held_size = frame.read_var_int
    held = Minecraft::IO::Memory.new(Bytes.new(held_size).tap { |bytes| frame.read_fully(bytes) })
    expect(held.read_var_int).to eq(Rosegold::Serverbound::HeldItemChange.packet_id_for_protocol(Rosegold::Client.protocol_version))
    expect(held.read_short).to eq(4_i16)
    action_size = frame.read_var_int
    action = Minecraft::IO::Memory.new(Bytes.new(action_size).tap { |bytes| frame.read_fully(bytes) })
    expect(action.read_var_int).to eq(Rosegold::Serverbound::PlayerAction.packet_id_for_protocol(Rosegold::Client.protocol_version))
    expected_swap_action = Rosegold::Client.protocol_version >= 777_u32 ? 7_u32 : 6_u32
    expect(action.read_var_int).to eq(expected_swap_action)
  end

  it "accepts reversed SetContainerContent confirmation using decoded equivalent components" do
    bot, client, _, _ = play_bot
    main = damaged_slot(1_u32, 7_u32)
    offhand = damaged_slot(2_u32, 11_u32)
    client.inventory_menu[36] = main
    client.inventory_menu[45] = offhand

    spawn do
      sleep 2.milliseconds
      # New component instances emulate a decoded server packet rather than reusing local objects.
      deliver client, content_update(0_u32, swapped_slots(
        damaged_slot(2_u32, 11_u32), damaged_slot(1_u32, 7_u32)))
    end

    bot.swap_hands(100.milliseconds)
    expect(client.inventory_menu[36].damage).to eq(11_u32)
    expect(client.inventory_menu[45].damage).to eq(7_u32)
  end

  it "does not let unrelated windows or one hand alone confirm the swap" do
    bot, client, _, _ = play_bot
    main = Rosegold::Slot.new(1_u32, 1_u32)
    offhand = Rosegold::Slot.new(1_u32, 2_u32)
    client.inventory_menu[36] = main
    client.inventory_menu[45] = offhand

    spawn do
      sleep 2.milliseconds
      deliver client, slot_update(3_i8, 36, offhand)
      deliver client, slot_update(0_i8, 36, offhand)
      sleep 4.milliseconds
      deliver client, slot_update(0_i8, 45, main)
    end

    bot.swap_hands(100.milliseconds)
    expect(client.inventory_menu[36].item_id_int).to eq(2_u32)
    expect(client.inventory_menu[45].item_id_int).to eq(1_u32)
  end

  it "closes an open container before synchronizing selection and swapping hands" do
    bot, client, _, io = play_bot
    main = Rosegold::Slot.new(1_u32, 1_u32)
    offhand = Rosegold::Slot.new(1_u32, 2_u32)
    client.inventory_menu[36] = main
    client.inventory_menu[45] = offhand
    container = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Test Chest"), rows: 1)
    client.container_menu = container

    spawn do
      sleep 2.milliseconds
      deliver client, slot_update(0_i8, 45, main)
      deliver client, slot_update(0_i8, 36, offhand)
    end

    bot.swap_hands(100.milliseconds)
    expect(bot.container_type).to be_nil
    expect(client.inventory_menu[36].item_id_int).to eq(2_u32)
    expect(client.inventory_menu[45].item_id_int).to eq(1_u32)

    frame = Minecraft::IO::Memory.new(io.to_slice)
    packet_ids = [] of UInt32
    until frame.pos == frame.size
      packet_size = frame.read_var_int
      packet = Minecraft::IO::Memory.new(Bytes.new(packet_size).tap { |bytes| frame.read_fully(bytes) })
      packet_ids << packet.read_var_int
    end
    expect(packet_ids).to eq([
      Rosegold::Serverbound::CloseWindow.packet_id_for_protocol(Rosegold::Client.protocol_version),
      Rosegold::Serverbound::HeldItemChange.packet_id_for_protocol(Rosegold::Client.protocol_version),
      Rosegold::Serverbound::PlayerAction.packet_id_for_protocol(Rosegold::Client.protocol_version),
    ])
  end

  it "sends an action for identical stacks without redundantly re-synchronizing the selection" do
    bot, client, _, io = play_bot
    client.player.hotbar_selection = 4_u32
    identical = damaged_slot(1_u32, 7_u32)
    client.inventory_menu[40] = identical
    client.inventory_menu[45] = damaged_slot(1_u32, 7_u32)

    bot.swap_hands
    bot.swap_hands

    frame = Minecraft::IO::Memory.new(io.to_slice)
    packet_ids = [] of UInt32
    until frame.pos == frame.size
      packet_size = frame.read_var_int
      packet = Minecraft::IO::Memory.new(Bytes.new(packet_size).tap { |bytes| frame.read_fully(bytes) })
      packet_ids << packet.read_var_int
    end
    expect(packet_ids).to eq([
      Rosegold::Serverbound::HeldItemChange.packet_id_for_protocol(Rosegold::Client.protocol_version),
      Rosegold::Serverbound::PlayerAction.packet_id_for_protocol(Rosegold::Client.protocol_version),
      Rosegold::Serverbound::PlayerAction.packet_id_for_protocol(Rosegold::Client.protocol_version),
    ])
  end

  it "sends one action and returns without deltas when both hands are empty" do
    bot, client, _, io = play_bot
    client.inventory_menu[36] = Rosegold::Slot.new
    client.inventory_menu[45] = Rosegold::Slot.new

    bot.swap_hands(10.milliseconds)

    frame = Minecraft::IO::Memory.new(io.to_slice)
    action_count = 0
    until frame.pos == frame.size
      packet_size = frame.read_var_int
      packet = Minecraft::IO::Memory.new(Bytes.new(packet_size).tap { |bytes| frame.read_fully(bytes) })
      action_count += 1 if packet.read_var_int == Rosegold::Serverbound::PlayerAction.packet_id_for_protocol(Rosegold::Client.protocol_version)
    end
    expect(action_count).to eq(1)
    expect(client.inventory_menu[36].empty?).to be_true
    expect(client.inventory_menu[45].empty?).to be_true
  end

  it "times out, removes temporary listeners, and releases the overlapping-call lock" do
    bot, client, _, _ = play_bot
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
    client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
    original_slot_handlers = client.event_handlers[Rosegold::Clientbound::SetSlot].size
    original_content_handlers = client.event_handlers[Rosegold::Clientbound::SetContainerContent].size

    expect { bot.swap_hands(3.milliseconds) }.to raise_error(Exception, /Timed out waiting for hand swap/)
    expect(client.event_handlers[Rosegold::Clientbound::SetSlot].size).to eq(original_slot_handlers)
    expect(client.event_handlers[Rosegold::Clientbound::SetContainerContent].size).to eq(original_content_handlers)

    overlapping_error = nil
    spawn do
      sleep 2.milliseconds
      begin
        bot.swap_hands(10.milliseconds)
      rescue ex
        overlapping_error = ex
      end
      deliver client, slot_update(0_i8, 45, Rosegold::Slot.new(1_u32, 1_u32))
      deliver client, slot_update(0_i8, 36, Rosegold::Slot.new(1_u32, 2_u32))
    end
    bot.swap_hands(100.milliseconds)
    expect(overlapping_error.try(&.message)).to eq("A hand swap is already in progress")
  end

  it "fails promptly and cleans up when the client disconnects before confirmation" do
    bot, client, connection, _ = play_bot
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
    client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
    original_slot_handlers = client.event_handlers[Rosegold::Clientbound::SetSlot].size

    spawn do
      sleep 2.milliseconds
      connection.disconnect("test disconnect")
    end

    expect { bot.swap_hands(100.milliseconds) }.to raise_error(Rosegold::Client::NotConnected, /Disconnected while swapping hands/)
    expect(client.event_handlers[Rosegold::Clientbound::SetSlot].size).to eq(original_slot_handlers)
  end

  it "does not send a swap action while spectating" do
    bot, client, _, io = play_bot
    client.player.gamemode = 3_i8
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
    client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)

    bot.swap_hands
    expect(io.size).to eq(0)
  end
end
