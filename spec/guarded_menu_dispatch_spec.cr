require "./spec_helper"

private class GuardedMenuSink < ::IO
  getter memory = ::IO::Memory.new
  getter entered = Channel(Nil).new(1)
  property gate : Channel(Nil)?
  property? fail = false
  getter writes = 0

  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
    @writes += 1
    if gate = @gate
      @gate = nil
      entered.send(nil)
      gate.receive
    end
    memory.write slice
    raise ::IO::Error.new("incomplete write") if fail?
  end
end

private class GuardedMenuClient < Rosegold::Client
  getter sink = GuardedMenuSink.new

  def initialize
    super("localhost")
    @connection = Rosegold::Connection::Client.new(Minecraft::IO::Wrap.new(sink), Rosegold::ProtocolState::PLAY, protocol_version, self)
    set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def chest(id = 1_u8)
    Rosegold::ChestMenu.new(self, id, Rosegold::Chat.new("Chest"), 1)
  end

  def reconnect(next_sink : GuardedMenuSink) : Nil
    connection.disconnect("test")
    attach(next_sink)
  end

  def attach(next_sink : GuardedMenuSink) : Nil
    @connection = Rosegold::Connection::Client.new(Minecraft::IO::Wrap.new(next_sink), Rosegold::ProtocolState::PLAY, protocol_version, self)
    set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def stack(count : UInt32)
    Rosegold::Slot.new(count, Rosegold::MCData.default.items.find! { |item| item.name == "stone" }.id)
  end

  def frames
    io = Minecraft::IO::Memory.new(sink.memory.to_slice.dup)
    result = [] of Minecraft::IO::Memory
    while io.pos < io.size
      payload = Bytes.new(io.read_var_int)
      io.read_fully(payload)
      result << Minecraft::IO::Memory.new(payload)
    end
    result
  end
end

private class GuardedClickHookClient < GuardedMenuClient
  getter captured = [] of Rosegold::Serverbound::Packet

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    super if connected?
    captured << packet
    :captured
  end
end

private class BatchingClickHookClient < GuardedMenuClient
  getter serialized = [] of Bytes

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    return super unless packet.is_a?(Rosegold::Serverbound::ClickWindow)

    serialized << packet.write
    super Rosegold::Serverbound::ClientTickEnd.new
    Fiber.yield
    super
    :hooked
  end
end

private class DelegatingClickHookClient < GuardedMenuClient
  def send_packet!(packet : Rosegold::Serverbound::Packet)
    return super unless packet.is_a?(Rosegold::Serverbound::ClickWindow)

    done = Channel(Nil).new(1)
    spawn do
      connection.send_packet(packet)
      done.send(nil)
    end
    select
    when done.receive
      :delegated
    when timeout(1.second)
      :timed_out
    end
  end
end

private class RaisingWriteMenu < Rosegold::ChestMenu
  property? raise_after_write = false

  def []=(index : Int32, slot : Rosegold::Slot)
    super
    return unless raise_after_write?

    @raise_after_write = false
    raise "builder failed"
  end
end

private class YieldingClickMenu < Rosegold::ChestMenu
  getter building = Channel(Nil).new(1)
  getter resume = Channel(Nil).new(1)
  @pause_pickup = true

  def may_pickup?(slot_index : Int32) : Bool
    if @pause_pickup
      @pause_pickup = false
      building.send(nil)
      resume.receive
    end
    super
  end
end

private def await_menu_dispatch(channel : Channel(T)) : T forall T
  select
  when result = channel.receive
    result
  when timeout(2.seconds)
    raise "Timed out waiting on the guarded menu test"
  end
end

private def queue_menu_dispatch(&dispatch : -> Bool)
  result = Channel(Bool | Exception).new(1)
  spawn do
    begin
      result.send(dispatch.call)
    rescue ex
      result.send(ex)
    end
  end
  Fiber.yield
  result
end

Spectator.describe "guarded menu dispatch" do
  let(client) { GuardedMenuClient.new }
  let(session) { client.play_session? || fail("Expected a PLAY session") }
  let(menu) { client.inventory_menu }
  let(op) { Rosegold::ClickOperation::LeftClick }

  it "runs Disconnected listeners after a failed ordinary click releases the write lock" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    app = Mutex.new
    listened = Channel(Nil).new(1)
    client.on(Rosegold::Event::Disconnected) do
      app.synchronize { }
      listened.send(nil)
    end
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    await_menu_dispatch(client.sink.entered)
    holding = Channel(Nil).new(1)
    queued = Channel(Exception?).new(1)
    spawn do
      app.synchronize do
        holding.send(nil)
        client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
        queued.send(nil)
      rescue ex
        queued.send(ex)
      end
    end
    await_menu_dispatch(holding)
    Fiber.yield
    client.sink.fail = true
    gate.send(nil)

    await_menu_dispatch(listened)
    expect(await_menu_dispatch(click)).to be_a(IO::Error)
    expect(await_menu_dispatch(queued)).to be_a(Rosegold::Client::NotConnected)
    expect(client.sink.writes).to eq(1)
  end

  it "settles a failed guarded click before Disconnected listeners run" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    app = Mutex.new
    listened = Channel(Exception?).new(1)
    client.on(Rosegold::Event::Disconnected) do
      app.synchronize { }
      begin
        menu.send_click(37, op)
        listened.send(nil)
      rescue ex
        listened.send(ex)
      end
    end
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    guarded = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    holding = Channel(Nil).new(1)
    ordinary = Channel(Exception?).new(1)
    spawn do
      app.synchronize do
        holding.send(nil)
        menu.send_click(37, op)
        ordinary.send(nil)
      rescue ex
        ordinary.send(ex)
      end
    end
    await_menu_dispatch(holding)
    Fiber.yield
    client.sink.fail = true
    gate.send(nil)

    expect(await_menu_dispatch(listened)).to be_a(Rosegold::Client::NotConnected)
    expect(await_menu_dispatch(guarded)).to be_a(IO::Error)
    expect(await_menu_dispatch(ordinary)).to be_a(Rosegold::Client::NotConnected)
    expect(client.sink.writes).to eq(1)
    expect(menu[36].count).to eq(6_u32)
  end

  it "lets an ordinary click hook wait for another fiber to write the click" do
    hooked = DelegatingClickHookClient.new
    inventory = hooked.inventory_menu
    inventory.update_slot(36, hooked.stack(6_u32), 5_u32)
    result = Channel(Symbol?).new(1)
    spawn { result.send(inventory.send_click(36, op).as(Symbol?)) }

    expect(await_menu_dispatch(result)).to eq(:delegated)
    picked = Rosegold::Serverbound::ClickWindow.new(
      Rosegold::Serverbound::ClickWindow::Mode::Click, 0_i8, 36_i16,
      [Rosegold::WindowSlot.new(36, Rosegold::Slot.new)], inventory.id, 5, hooked.stack(6_u32))
    expect(hooked.frames.map(&.to_slice)).to eq([picked.write])
  end

  it "raises NotConnected for an ordinary click queued behind a failed write" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    ordinary = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    client.sink.fail = true
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_a(IO::Error)
    expect(await_menu_dispatch(ordinary)).to be_a(Rosegold::Client::NotConnected)
    expect(client.sink.writes).to eq(1)
  end

  it "refuses an overlapping guarded intent at once instead of queuing it" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    first = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    second = queue_menu_dispatch { menu.send_click_if!(37, op, session) { true } }
    expect(await_menu_dispatch(second)).to be_false
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(first)).to be_true
    expect(client.frames.size).to eq(2)
    expect(menu[36].empty?).to be_true
    expect(menu.cursor.count).to eq(6_u32)
  end

  it "does not hold an ordinary click behind a guarded click that is only queued" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    guarded = queue_menu_dispatch { menu.send_click_if!(37, op, session) { true } }
    ordinary = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    expect(menu[36].empty?).to be_true
    expect(menu.cursor.count).to eq(6_u32)
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(await_menu_dispatch(guarded)).to be_false
    expect(client.frames.size).to eq(2)
    expect(menu[37].empty?).to be_true
  end

  it "raises NotConnected for an ordinary click that waited out a flush across a reconnect" do
    chest = client.chest
    client.container_menu = chest
    slot = chest.hotbar_slot_index(0)
    chest.update_slot(slot, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    await_menu_dispatch(client.sink.entered)
    ordinary = queue_menu_dispatch do
      chest.send_click(slot, op)
      true
    end
    next_sink = GuardedMenuSink.new
    client.reconnect(next_sink)
    gate.send(nil)

    expect(await_menu_dispatch(close)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_a(Rosegold::Client::NotConnected)
    expect(client.frames.size).to eq(1)
    expect(next_sink.writes).to eq(0)
    expect(chest[slot].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "raises NotConnected for an ordinary click started outside PLAY that waited into the next session" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    chest = client.chest
    client.container_menu = chest
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    await_menu_dispatch(client.sink.entered)
    client.connection.disconnect("test")
    expect(client.play_session?).to be_nil
    expect(client.container_menu.same?(menu)).to be_true
    ordinary = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    next_sink = GuardedMenuSink.new
    client.attach(next_sink)
    gate.send(nil)

    await_menu_dispatch(close)
    expect(await_menu_dispatch(ordinary)).to be_a(Rosegold::Client::NotConnected)
    expect(next_sink.writes).to eq(0)
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
  end

  it "skips an ordinary click that waited out the close retiring its menu" do
    chest = client.chest
    client.container_menu = chest
    slot = chest.hotbar_slot_index(0)
    chest.update_slot(slot, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    await_menu_dispatch(client.sink.entered)
    ordinary = Channel(Bool?).new(1)
    spawn { ordinary.send(chest.send_click(slot, op).nil?) }
    Fiber.yield
    gate.send(nil)

    expect(await_menu_dispatch(close)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(client.frames.size).to eq(1)
    expect(client.container_menu.same?(menu)).to be_true
    expect(menu[36].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "skips an ordinary click that waited out a flush while the server replaced its menu" do
    chest = client.chest
    client.container_menu = chest
    slot = chest.hotbar_slot_index(0)
    chest.update_slot(slot, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    guarded = queue_menu_dispatch { chest.send_click_if!(0, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    ordinary = Channel(Bool?).new(1)
    spawn { ordinary.send(chest.send_click(slot, op).nil?) }
    Fiber.yield
    replacement = client.chest(2_u8)
    client.container_menu = replacement
    slots = Array.new(replacement.total_slots) do |index|
      Rosegold::WindowSlot.new(index, index == replacement.hotbar_slot_index(0) ? client.stack(6_u32) : Rosegold::Slot.new)
    end
    Rosegold::Clientbound::SetContainerContent.new(2_u32, 1_u32, slots, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(guarded)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(client.frames.size).to eq(1)
    expect(replacement[replacement.hotbar_slot_index(0)].count).to eq(6_u32)
    expect(menu[36].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "refuses a queued guarded click after an ordinary builder raises mid-prediction" do
    chest = client.chest
    client.container_menu = chest
    slot = chest.hotbar_slot_index(0)
    chest.update_slot(slot, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    guarded = queue_menu_dispatch { chest.send_click_if!(0, op, session) { true } }
    expect { chest.send_click(slot, 128, :click) }.to raise_error(OverflowError)
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(guarded)).to be_false
    expect(client.frames.size).to eq(1)
  end

  it "refuses a queued guarded click after an ordinary hotbar swap builder raises" do
    chest = RaisingWriteMenu.new(client, 1_u8, Rosegold::Chat.new("Chest"), 1)
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    guarded = queue_menu_dispatch { chest.send_click_if!(1, op, session) { true } }
    chest.raise_after_write = true
    expect { chest.swap_hotbar(0, 0) }.to raise_error(Exception, "builder failed")
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(guarded)).to be_false
    expect(client.frames.size).to eq(1)
  end

  it "rechecks caller authority behind another writer without predicting a refused click" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    authorized = true
    checked = false
    click = queue_menu_dispatch do
      menu.send_click_if!(36, op, session) do
        checked = true
        authorized
      end
    end
    expect(checked).to be_false
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
    authorized = false
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(click)).to be_false
    expect(checked).to be_true
    expect(client.frames.size).to eq(1)
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
  end

  it "refuses a queued click after an authoritative same-state-ID player slot update" do
    chest = client.chest
    client.container_menu = chest
    slot = chest.hotbar_slot_index(0)
    chest.update_slot(slot, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    click = queue_menu_dispatch { chest.send_click_if!(slot, op, session) { true } }
    Rosegold::Clientbound::SetPlayerInventory.new(0, client.stack(2_u32)).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(click)).to be_false
    expect(client.frames.size).to eq(1)
    expect(chest[slot].count).to eq(2_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "refuses queued click and close against a replacement with the same window ID" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    click = queue_menu_dispatch { chest.send_click_if!(0, op, session) { true } }
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    replacement = client.chest
    client.container_menu = replacement
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(click)).to be_false
    expect(await_menu_dispatch(close)).to be_false
    expect(client.frames.size).to eq(1)
    expect(client.container_menu.same?(replacement)).to be_true
    expect(chest[0].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "refuses a click queued for a previous PLAY session even with the same player menu" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    old_session = session
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    click = queue_menu_dispatch { menu.send_click_if!(36, op, old_session) { true } }
    client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(click)).to be_false
    expect(client.frames.size).to eq(1)
    expect(client.container_menu.same?(menu)).to be_true
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
  end

  it "refuses if caller authority expires while the detached click is building" do
    chest = YieldingClickMenu.new(client, 1_u8, Rosegold::Chat.new("Chest"), 1)
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    authorized = true
    click = queue_menu_dispatch { chest.send_click_if!(0, op, session) { authorized } }
    await_menu_dispatch(chest.building)
    authorized = false
    chest.resume.send(nil)

    expect(await_menu_dispatch(click)).to be_false
    expect(client.frames).to be_empty
    expect(chest[0].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
  end

  it "writes the original click payload and applies prediction only after the write" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(menu[36].empty?).to be_true
    expect(menu.cursor.count).to eq(6_u32)
    expected = Rosegold::Serverbound::ClickWindow.new(
      Rosegold::Serverbound::ClickWindow::Mode::Click, 0_i8, 36_i16,
      [Rosegold::WindowSlot.new(36, Rosegold::Slot.new)], menu.id, 5, client.stack(6_u32))
    expect(client.frames.map(&.to_slice)).to eq([expected.write])
  end

  it "uses the real container's shift routing and publishes to shared player slots" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { chest.send_click_if!(0, Rosegold::ClickOperation::ShiftClick, session) { true } }
    await_menu_dispatch(client.sink.entered)
    expect(chest[0].count).to eq(6_u32)
    expect(menu[44].empty?).to be_true
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(chest[0].empty?).to be_true
    expect(menu[44].count).to eq(6_u32)
  end

  it "does not overwrite an authoritative slot update that lands during the write" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    Rosegold::Clientbound::SetPlayerInventory.new(0, client.stack(2_u32)).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(client.frames.size).to eq(1)
    expect(menu[36].count).to eq(2_u32)
    expect(menu.cursor.count).to eq(6_u32)
  end

  it "merges unrelated authoritative updates during the flush" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    Rosegold::Clientbound::SetPlayerInventory.new(1, client.stack(2_u32)).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(menu[36].empty?).to be_true
    expect(menu[37].count).to eq(2_u32)
    expect(menu.cursor.count).to eq(6_u32)
  end

  it "preserves a newer shared hotbar slot and cursor while committing the rest of a click" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { chest.send_click_if!(0, Rosegold::ClickOperation::SwapHotbar1, session) { true } }
    await_menu_dispatch(client.sink.entered)
    Rosegold::Clientbound::SetPlayerInventory.new(0, client.stack(2_u32)).callback(client)
    chest.update_slot(-1, client.stack(3_u32), 5_u32)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(chest[0].empty?).to be_true
    expect(menu[36].count).to eq(2_u32)
    expect(chest.cursor.count).to eq(3_u32)
  end

  it "applies a container-only delta when the shared player content is replaced" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { chest.send_click_if!(0, Rosegold::ClickOperation::SwapHotbar1, session) { true } }
    await_menu_dispatch(client.sink.entered)
    slots = Array.new(menu.total_slots) { |index| Rosegold::WindowSlot.new(index, client.stack(index == 36 ? 2_u32 : 0_u32)) }
    cursor = Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)
    Rosegold::Clientbound::SetContainerContent.new(0_u32, menu.state_id, slots, cursor).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(chest[0].empty?).to be_true
    expect(menu[36].count).to eq(2_u32)
  end

  it "leaves a newer cursor alone when the click predicted a cursor change" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    menu.update_slot(-1, client.stack(3_u32), 5_u32)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(menu[36].empty?).to be_true
    expect(menu.cursor.count).to eq(3_u32)
  end

  it "skips all deltas after invalidating the menu during the flush" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    menu.invalidate_content
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
  end

  it "builds a queued ordinary click after the guarded click commits" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    guarded = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    ordinary = queue_menu_dispatch do
      menu.send_click(37, op)
      true
    end
    expect(menu[36].count).to eq(6_u32)
    expect(menu[37].empty?).to be_true
    expect(menu.cursor.empty?).to be_true
    gate.send(nil)

    expect(await_menu_dispatch(guarded)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(menu[36].empty?).to be_true
    expect(menu[37].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
    placed = Rosegold::Serverbound::ClickWindow.new(
      Rosegold::Serverbound::ClickWindow::Mode::Click, 0_i8, 37_i16,
      [Rosegold::WindowSlot.new(37, client.stack(6_u32))], menu.id, 5, Rosegold::Slot.new)
    expect(client.frames[1].to_slice).to eq(placed.write)
  end

  it "refuses a queued guarded intent superseded by an ordinary click" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    ordinary = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    guarded = queue_menu_dispatch { menu.send_click_if!(37, op, session) { true } }
    expect(await_menu_dispatch(guarded)).to be_false
    expect(menu[36].empty?).to be_true
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(client.frames.size).to eq(2)
    expect(menu[36].empty?).to be_true
    expect(menu[37].empty?).to be_true
    expect(menu.cursor.count).to eq(6_u32)
  end

  it "keeps ordinary click dispatch hooks and their return value in and out of PLAY" do
    [true, false].each do |connected|
      hooked = GuardedClickHookClient.new
      hooked.connection.disconnect("test") unless connected
      inventory = hooked.inventory_menu
      inventory.update_slot(36, hooked.stack(6_u32), 5_u32)

      expect(inventory.send_click(36, op)).to eq(:captured)
      packet = hooked.captured.first.as(Rosegold::Serverbound::ClickWindow)
      expect(packet.state_id).to eq(5)
      expect(packet.changed_slots.map(&.slot_number)).to eq([36])
      expect(packet.cursor.count).to eq(6_u32)
      expect(inventory[36].empty?).to be_true
    end
  end

  it "does not predict into a replacement menu during a click flush" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { chest.send_click_if!(0, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    replacement = client.chest
    client.container_menu = replacement
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(chest[0].count).to eq(6_u32)
    expect(chest.cursor.empty?).to be_true
    expect(replacement[0].empty?).to be_true
    expect(replacement.cursor.empty?).to be_true
  end

  it "keeps predictions detached when the builder or write raises" do
    menu.update_slot(36, client.stack(6_u32), UInt32::MAX)
    expect { menu.send_click_if!(36, op, session) { true } }.to raise_error(OverflowError)
    expect(client.connection.open?).to be_true
    expect(client.sink.writes).to eq(0)
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true

    menu.state_id = 5_u32
    client.sink.fail = true
    expect { menu.send_click_if!(36, op, session) { true } }.to raise_error(IO::Error)
    expect(session.connection.open?).to be_false
    expect(client.sink.writes).to eq(1)
    expect(menu[36].count).to eq(6_u32)
    expect(menu.cursor.empty?).to be_true
  end

  it "retires a sent close before the next queued click checks the menu" do
    chest = client.chest
    client.container_menu = chest
    chest.update_slot(0, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    await_menu_dispatch(client.sink.entered)
    click = queue_menu_dispatch { chest.send_click_if!(0, op, session) { true } }
    gate.send(nil)

    expect(await_menu_dispatch(close)).to be_true
    expect(await_menu_dispatch(click)).to be_false
    expect(client.frames.size).to eq(1)
    expect(client.container_menu.same?(menu)).to be_true
    expect(chest[0].count).to eq(6_u32)
  end

  it "reports a sent close even if the reader installed a replacement while writing" do
    chest = client.chest
    client.container_menu = chest
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    closed = [] of UInt32
    client.on(Rosegold::Event::ContainerClosed) { |event| closed << event.window_id }
    close = queue_menu_dispatch { chest.close_if!(session) { true } }
    await_menu_dispatch(client.sink.entered)
    replacement = client.chest
    client.container_menu = replacement
    gate.send(nil)

    expect(await_menu_dispatch(close)).to be_true
    expect(client.frames.map(&.to_slice)).to eq([Rosegold::Serverbound::CloseWindow.new(chest.id.to_u16).write])
    expect(client.container_menu.same?(replacement)).to be_true
    expect(closed).to be_empty
    expect(replacement.close_if!(session) { false }).to be_false
    expect(replacement.close_if!(session) { true }).to be_true
    expect(client.container_menu.same?(menu)).to be_true
    expect(closed).to eq([replacement.id.to_u32])
  end

  it "keeps a shared slot updated through another menu while a player menu click flushes" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    click = queue_menu_dispatch { menu.send_click_if!(36, op, session) { true } }
    await_menu_dispatch(client.sink.entered)
    chest = client.chest
    client.container_menu = chest
    slot = Rosegold::WindowSlot.new(chest.hotbar_slot_index(0), client.stack(2_u32))
    Rosegold::Clientbound::SetSlot.new(chest.id.to_i8, 6_u32, slot).callback(client)
    Rosegold::Clientbound::CloseWindow.new(chest.id.to_u32).callback(client)
    gate.send(nil)

    expect(await_menu_dispatch(click)).to be_true
    expect(client.container_menu.same?(menu)).to be_true
    expect(menu[36].count).to eq(2_u32)
    expect(menu.cursor.count).to eq(6_u32)
  end

  it "builds an ordinary click when called and keeps an update that lands while it waits to write" do
    menu.update_slot(36, client.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    client.sink.gate = gate
    blocker = queue_menu_dispatch do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(client.sink.entered)
    ordinary = queue_menu_dispatch do
      menu.send_click(36, op)
      true
    end
    menu.update_slot(10, client.stack(1_u32), 6_u32)
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(ordinary)).to be_true
    expect(menu[36].empty?).to be_true
    expect(menu[10].count).to eq(1_u32)
    expect(menu.cursor.count).to eq(6_u32)
    picked = Rosegold::Serverbound::ClickWindow.new(
      Rosegold::Serverbound::ClickWindow::Mode::Click, 0_i8, 36_i16,
      [Rosegold::WindowSlot.new(36, Rosegold::Slot.new)], menu.id, 5, client.stack(6_u32))
    expect(client.frames.map(&.to_slice)).to eq([Rosegold::Serverbound::ClientTickEnd.new.write, picked.write])
  end

  it "shows a queued ordinary click hook the packet it writes" do
    hooked = BatchingClickHookClient.new
    inventory = hooked.inventory_menu
    inventory.update_slot(36, hooked.stack(6_u32), 5_u32)
    gate = Channel(Nil).new(1)
    hooked.sink.gate = gate
    blocker = queue_menu_dispatch do
      hooked.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      true
    end
    await_menu_dispatch(hooked.sink.entered)
    result = Channel(Symbol?).new(1)
    spawn { result.send(inventory.send_click(36, op).as(Symbol?)) }
    Fiber.yield
    inventory.update_slot(10, hooked.stack(1_u32), 6_u32)
    other = queue_menu_dispatch do
      hooked.send_packet! Rosegold::Serverbound::HeldItemChange.new(3_i16)
      true
    end
    gate.send(nil)

    expect(await_menu_dispatch(blocker)).to be_true
    expect(await_menu_dispatch(result)).to eq(:hooked)
    expect(await_menu_dispatch(other)).to be_true
    tick = Rosegold::Serverbound::ClientTickEnd.new.write
    picked = Rosegold::Serverbound::ClickWindow.new(
      Rosegold::Serverbound::ClickWindow::Mode::Click, 0_i8, 36_i16,
      [Rosegold::WindowSlot.new(36, Rosegold::Slot.new)], inventory.id, 5, hooked.stack(6_u32))
    expect(hooked.serialized).to eq([picked.write])
    frames = hooked.frames.map(&.to_slice)
    expect(frames.size).to eq(4)
    expect(frames.first).to eq(tick)
    expect(frames.count(picked.write)).to eq(1)
    expect(frames.includes?(Rosegold::Serverbound::HeldItemChange.new(3_i16).write)).to be_true
    expect(frames.index!(picked.write)).to be > frames.index!(tick, 1)
  end
end
