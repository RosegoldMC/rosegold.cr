require "./spec_helper"

class AuthoritySpecSink < ::IO
  getter memory = ::IO::Memory.new
  property gate : Channel(Nil)?
  property? fail = false
  getter entered = Channel(Nil).new(1)

  def initialize(@source : ::IO? = nil)
  end

  def read(slice : Bytes)
    @source.try(&.read(slice)) || 0
  end

  def write(slice : Bytes) : Nil
    if gate = @gate
      @gate = nil
      entered.send(nil)
      gate.receive
    end
    raise ::IO::Error.new("boom") if fail?
    memory.write slice
  end
end

class AuthoritySpecClient < Rosegold::Client
  getter sink : AuthoritySpecSink

  def initialize(source : ::IO? = nil)
    super("localhost", offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "authority"})
    @sink = AuthoritySpecSink.new(source)
    @connection = Rosegold::Connection::Client.new(Minecraft::IO::Wrap.new(@sink), Rosegold::ProtocolState::PLAY, protocol_version, self)
    set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def start_reader_for_test
    start_reader connection
  end

  def physics_for_test
    physics
  end

  def interactions_for_test
    interactions
  end

  def frame_payloads : Array(Bytes)
    io = Minecraft::IO::Memory.new(sink.memory.to_slice.dup)
    payloads = [] of Bytes
    while io.pos < io.size
      payload = Bytes.new(io.read_var_int)
      io.read_fully(payload)
      payloads << payload
    end
    payloads
  end

  def frame_ids : Array(UInt32)
    io = Minecraft::IO::Memory.new(sink.memory.to_slice.dup)
    ids = [] of UInt32
    while io.pos < io.size
      payload = Bytes.new(io.read_var_int)
      io.read_fully(payload)
      ids << Minecraft::IO::Memory.new(payload).read_var_int
    end
    ids
  end

  def release_tick
    manual_control.before_tick
    manual_control.after_tick
  end
end

class AuthoritySpecHost
  include Rosegold::ManualControl::Host

  def manual_control_enabled? : Bool
    true
  end
end

class OpeningSpecBot < Rosegold::Bot
  property opened : Rosegold::ContainerMenu?
  property wait_error : Exception?
  property opening : Proc(OpeningSpecBot, Nil)?

  def use_hand(target : Rosegold::Vec3d? | Rosegold::Look? = nil, hand : Rosegold::Hand? = nil)
    if custom = opening
      return custom.call(self)
    end
    @opened = open_window(2_u8)
  end

  def open_window(id : UInt8) : Rosegold::ChestMenu
    menu = Rosegold::ChestMenu.new(client, id, Rosegold::Chat.new("Chest"), 1)
    client.container_menu = menu
    content(id.to_u32)
    menu
  end

  def content(window_id : UInt32)
    client.emit_event Rosegold::Clientbound::SetContainerContent.new(window_id, 1_u32,
      [] of Rosegold::WindowSlot, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
  end

  def wait_tick
    if error = wait_error
      raise error
    end
  end

  def table_for_test(&)
    with_table(Rosegold::Vec3i.new(0, 0, 2)) { yield }
  end
end

class DigSpecBot < Rosegold::Bot
  property on_wait : Proc(Nil)?

  def wait_tick
    on_wait.try &.call
  end
end

Spectator.describe "native authority" do
  def id(type)
    type.packet_id_for_protocol(Rosegold::Client.protocol_version)
  end

  def wait_until(limit = 1.second, &)
    deadline = Time.instant + limit
    until yield
      fail "condition not met" if Time.instant > deadline
      sleep 1.millisecond
    end
  end

  def releasing(client)
    client.manual_control.grant || fail("grant refused")
    client.manual_control.revoke
  end

  describe "connection write failure" do
    it "disconnects after releasing the write lock, so a listener can wait on a queued writer" do
      client = AuthoritySpecClient.new
      app = Mutex.new
      listened = Channel(Nil).new(1)
      client.on(Rosegold::Event::Disconnected) do |_|
        app.synchronize { }
        listened.send nil
      end

      gate = Channel(Nil).new
      client.sink.gate = gate
      first = Channel(Bool).new(1)
      spawn { first.send client.chat_manager.send_message("hello") }
      client.sink.entered.receive

      holding = Channel(Nil).new(1)
      queued = Channel(Exception?).new(1)
      spawn do
        app.synchronize do
          holding.send nil
          client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
          queued.send nil
        rescue error
          queued.send error
        end
      end
      holding.receive
      sleep 5.milliseconds

      client.sink.fail = true
      gate.send nil

      select
      when listened.receive
      when timeout(1.second)
        fail "Disconnected listener deadlocked behind the writer lock"
      end
      expect(first.receive).to be_false
      expect(queued.receive).to be_a(Rosegold::Client::NotConnected)
      expect(client.sink.memory.size).to eq 0
      expect(client.connection?.try(&.close_reason).to_s).to contain("boom")
    end
  end

  describe "release waits" do
    it "never blocks the packet reader on a frozen release" do
      source, feed = IO.pipe
      client = AuthoritySpecClient.new(source)
      bot = Rosegold::Bot.new(client)
      releasing client
      elapsed = [] of Time::Span
      client.on(Rosegold::Clientbound::KeepAlive) do |_|
        started = Time.instant
        bot.start_digging
        client.physics_for_test.keys.press Rosegold::MovementKeys::Key::Forward
        elapsed << Time.instant - started
      end
      client.start_reader_for_test

      2.times do |index|
        payload = Rosegold::Clientbound::KeepAlive.new(index.to_i64).write
        frame = Minecraft::IO::Memory.new
        frame.write payload.size.to_u32
        frame.write payload
        feed.write frame.to_slice
      end

      wait_until(500.milliseconds) { elapsed.size == 2 }
      expect(elapsed.max).to be < 100.milliseconds
      expect(client.physics_for_test.keys.none?).to be_true
      expect(client.manual_control.releasing?).to be_true
    ensure
      client.try &.connection?.try &.disconnect("done")
      feed.try &.close
    end

    it "never blocks the ticker on a frozen release and does not force it" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      releasing client
      elapsed = [] of Time::Span
      client.on(Rosegold::Event::Tick) do |_|
        started = Time.instant
        bot.start_digging
        client.physics_for_test.keys.press Rosegold::MovementKeys::Key::Forward
        elapsed << Time.instant - started
      end
      client.start_ticker

      wait_until { elapsed.size >= 3 }
      expect(elapsed.max).to be < 100.milliseconds
      expect(client.physics_for_test.keys.none?).to be_true
      expect(client.manual_control.releasing?).to be_true
    ensure
      client.try &.connection?.try &.disconnect("done")
    end
  end

  describe "hand mutations" do
    it "writes a queued drop and pick only while the original authority and session hold" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      bot.drop_hand_single
      bot.pick_item_from_block(Rosegold::Vec3i.new(1, 2, 3))
      wait_until { client.frame_ids.includes?(id(Rosegold::Serverbound::PickItemFromBlock)) }
      expect(client.frame_ids).to contain(id(Rosegold::Serverbound::PlayerAction))
    end

    it "drops a queued drop when a grant starts before it is written" do
      client = AuthoritySpecClient.new
      Rosegold::Bot.new(client).drop_hand_full
      client.manual_control.grant
      5.times { Fiber.yield }
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::PlayerAction))
    end

    it "drops a queued drop when a grant started and fully released before it is written" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      Rosegold::Bot.new(client).drop_hand_single
      releasing client
      client.release_tick
      expect(client.manual_control.owns_input?).to be_false
      5.times { Fiber.yield }
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::PlayerAction))
    end

    it "drops a queued pick when the PLAY session changes before it is written" do
      client = AuthoritySpecClient.new
      Rosegold::Bot.new(client).pick_item_from_block(Rosegold::Vec3i.new(1, 2, 3))
      client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
      client.set_protocol_state(Rosegold::ProtocolState::PLAY)
      5.times { Fiber.yield }
      expect(client.frame_ids).to be_empty
    end

    it "ignores a hand swap while a controller holds input" do
      client = AuthoritySpecClient.new
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.manual_control.grant
      Rosegold::Bot.new(client).swap_hands(50.milliseconds)
      expect(client.frame_ids).to be_empty
      expect(client.container_menu).not_to eq(client.inventory_menu)
    end

    it "stops a hand swap whose queued close loses authority before the write" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.container_menu = chest

      gate = Channel(Nil).new
      client.sink.gate = gate
      spawn { client.send_packet! Rosegold::Serverbound::ClientTickEnd.new }
      client.sink.entered.receive
      done = Channel(Exception?).new(1)
      spawn do
        bot.swap_hands(200.milliseconds)
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      client.manual_control.grant
      gate.send nil

      select
      when result = done.receive
        expect(result).to be_nil
      when timeout(1.second)
        fail "swap did not return"
      end
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd)])
      expect(client.container_menu.same?(chest)).to be_true
    end
  end

  def reconfigure(client)
    client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def gate_writer(client) : Channel(Nil)
    gate = Channel(Nil).new
    client.sink.gate = gate
    spawn { client.send_packet! Rosegold::Serverbound::ClientTickEnd.new }
    client.sink.entered.receive
    gate
  end

  describe "opening capture" do
    it "rejects an opening that a second matching container replaced before the waiter resumed" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      second = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(opener : OpeningSpecBot) do
        opener.open_window(2_u8)
        second = opener.open_window(3_u8)
        nil
      end
      ran = false
      expect { bot.open_container { ran = true } }.to raise_error(Rosegold::Bot::ContainerOpenError)
      expect(ran).to be_false
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(second)).to be_true
    end

    it "waits past an inventory resync and another window's content for the opening's own content" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      chest = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(opener : OpeningSpecBot) do
        opener.content(0_u32)
        opener.content(9_u32)
        spawn do
          sleep 5.milliseconds
          chest = opener.open_window(2_u8)
        end
        nil
      end
      inside = nil.as(Rosegold::Menu?)
      bot.open_container { inside = client.container_menu }
      expect(inside.same?(chest)).to be_true
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
    end

    it "does not claim or close a container that opens in a later PLAY session" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      later = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(opener : OpeningSpecBot) do
        reconfigure(client)
        later = opener.open_window(2_u8)
        nil
      end
      ran = false
      expect { bot.open_container { ran = true } }.to raise_error(Rosegold::Bot::ContainerOpenError)
      expect(ran).to be_false
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(later)).to be_true
    end

    it "fails promptly when the PLAY session ends before any content arrives" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.opening = ->(_opener : OpeningSpecBot) do
        spawn do
          sleep 5.milliseconds
          reconfigure(client)
        end
        nil
      end
      started = Time.instant
      expect { bot.open_container(2.seconds) { } }.to raise_error(Rosegold::Bot::ContainerOpenError, /PLAY session ended/)
      expect(Time.instant - started).to be < 1.second
      expect(client.frame_ids).to be_empty
    end

    it "never writes an opening command behind the configuration acknowledgment" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      gate = gate_writer(client)
      spawn { Rosegold::Clientbound::StartConfiguration.new.callback(client) }
      Fiber.yield
      result = Channel(Exception?).new(1)
      spawn do
        bot.open_container_handle("/chest", 200.milliseconds) { |_| fail "no content" }
        result.send nil
      rescue error
        result.send error
      end
      Fiber.yield
      gate.send nil
      expect(result.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd), id(Rosegold::Serverbound::AcknowledgeConfiguration)])
    end

    it "sends an opening command in its own PLAY session and uses the container it opens" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      spawn do
        sleep 5.milliseconds
        bot.open_window(2_u8)
      end
      inside = nil.as(Rosegold::Menu?)
      bot.open_container_handle("/chest") { |_| inside = client.container_menu }
      expect(inside).to be_a(Rosegold::ChestMenu)
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ChatCommand), id(Rosegold::Serverbound::CloseWindow)])
    end

    it "does not dispatch an opening tap whose release wait spans a session reset" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      releasing client
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container { fail "no content" }
        done.send nil
      rescue error
        done.send error
      end
      sleep 10.milliseconds
      reconfigure(client)
      expect(done.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      client.interactions_for_test.tick
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::UseItem))
    end

    it "cleans up only in the PLAY session that delivered the content" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.open_container do
        reconfigure(client)
        if stale = bot.opened
          client.container_menu = stale
        end
      end
      expect(client.frame_ids).to be_empty
    end
  end

  describe "PLAY teardown" do
    it "retires the departing container locally once, with no close frame" do
      client = AuthoritySpecClient.new
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.container_menu = chest
      closed = [] of UInt32
      client.on(Rosegold::Event::ContainerClosed) { |event| closed << event.window_id }
      reconfigure(client)
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
      expect(closed).to eq([2_u32])
      expect(client.frame_ids).to be_empty
    end

    it "keeps a replacement a listener installs while the departing container retires" do
      client = AuthoritySpecClient.new
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      replacement = Rosegold::ChestMenu.new(client, 4_u8, Rosegold::Chat.new("Other"), 1)
      client.on(Rosegold::Event::ContainerClosed) { |_| client.container_menu = replacement }
      client.connection.disconnect("lost")
      expect(client.container_menu.same?(replacement)).to be_true
    end

    it "samples unresolved inventory from the departing container before retiring it" do
      client = AuthoritySpecClient.new
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.container_menu = chest
      chest.cursor = Rosegold::Slot.new(1_u32, 1_u32)
      control = client.manual_control
      control.bind_host AuthoritySpecHost.new
      outcome = Channel(Bool?).new(1)
      spawn do
        control.debug_until_returned
        outcome.send nil
      rescue error : Rosegold::ManualControl::Cancelled
        outcome.send error.unresolved_inventory?
      end
      Fiber.yield
      reconfigure(client)
      expect(outcome.receive).to be_true
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "finishes the transition and retirement despite a raising listener" do
      client = AuthoritySpecClient.new
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.on(Rosegold::Event::ContainerClosed) { |_| raise "listener failed" }
      client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
      expect(client.current_protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
      expect(client.connection.protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "still stops physics and runs later disconnect handlers when a listener raises" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.on(Rosegold::Event::ContainerClosed) { |_| raise "listener failed" }
      later = false
      client.on(Rosegold::Event::Disconnected) { |_| later = true }
      client.connection.disconnect("lost")
      expect(later).to be_true
      expect(client.physics_for_test.running?).to be_false
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "keeps the packet reader running through configuration when a listener raises" do
      source, feed = IO.pipe
      client = AuthoritySpecClient.new(source)
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.on(Rosegold::Event::ContainerClosed) { |_| raise "listener failed" }
      first_session = client.connection.play_session
      client.start_reader_for_test
      {Rosegold::Clientbound::StartConfiguration.new, Rosegold::Clientbound::FinishConfiguration.new}.each do |packet|
        payload = packet.write
        frame = Minecraft::IO::Memory.new
        frame.write payload.size.to_u32
        frame.write payload
        feed.write frame.to_slice
      end
      wait_until { client.connection.play_session > first_session }
      expect(client.current_protocol_state).to eq Rosegold::ProtocolState::PLAY
      expect(client.connected?).to be_true
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    ensure
      client.try &.connection?.try &.disconnect("done")
      feed.try &.close
    end

    it "announces the departing container once and writes no PLAY frame when a listener disconnects or writes" do
      client = AuthoritySpecClient.new
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      closed = [] of UInt32
      client.on(Rosegold::Event::ContainerClosed) do |event|
        closed << event.window_id
        client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
        client.connection.disconnect("listener")
      end
      client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
      expect(closed).to eq([2_u32])
      expect(client.frame_ids).to be_empty
      expect(client.current_protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "announces a sent close once when its listener disconnects" do
      client = AuthoritySpecClient.new
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.container_menu = chest
      closed = [] of UInt32
      client.on(Rosegold::Event::ContainerClosed) do |event|
        closed << event.window_id
        client.connection?.try &.disconnect("lost")
      end
      chest.close
      expect(closed).to eq([2_u32])
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "keeps a container open when its close is refused in the same session" do
      client = AuthoritySpecClient.new
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      client.container_menu = chest
      chest.close { false }
      expect(client.container_menu.same?(chest)).to be_true
      expect(client.frame_ids).to be_empty
    end
  end

  describe "guarded packet writes" do
    it "rechecks the PLAY session after the guard runs" do
      client = AuthoritySpecClient.new
      sent = client.send_packet_if!(Rosegold::Serverbound::CloseWindow.new(1_u16)) do
        reconfigure(client)
        true
      end
      expect(sent).to be_false
      expect(client.frame_ids).to be_empty
    end

    it "refuses a write whose guard disconnects and approves" do
      client = AuthoritySpecClient.new
      sent = client.send_packet_if!(Rosegold::Serverbound::CloseWindow.new(1_u16)) do
        client.connection.disconnect("guard")
        true
      end
      expect(sent).to be_false
      expect(client.frame_ids).to be_empty
    end

    it "neither writes nor commits when the readiness check leaves the connection closed" do
      client = AuthoritySpecClient.new
      conn = client.connection
      committed = false
      sent = conn.send_packet(-> { Rosegold::Serverbound::ClientTickEnd.new.write }, -> { committed = true; nil },
        -> { conn.disconnect("ready"); true })
      expect(sent).to be_false
      expect(committed).to be_false
      expect(client.frame_ids).to be_empty
    end

    it "refuses a guarded chat send whose guard disconnects and approves" do
      client = AuthoritySpecClient.new
      result = client.chat_manager.try_send_message("hello") do
        client.connection.disconnect("guard")
        true
      end
      expect(result).to eq Rosegold::SendResult::Refused
      expect(client.frame_ids).to be_empty
    end
  end

  describe "aimed compound actions" do
    def use_item_id
      id(Rosegold::Serverbound::UseItem)
    end

    def hold_item(client)
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
    end

    def whole_grant(client)
      client.release_tick
      client.manual_control.grant || fail("grant refused")
      client.manual_control.revoke
      client.release_tick
      client.physics_for_test.pause
    end

    def finish_release(client)
      client.release_tick
      client.physics_for_test.pause
    end

    def during_release_wait(client, &action : -> Nil)
      client.physics_for_test.unpause_for_spawn_chunk
      releasing client
      done = Channel(Exception?).new(1)
      spawn do
        action.call
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      done
    end

    it "drops an aimed tap when a session reset or a whole grant interrupts its aim" do
      {->(client : AuthoritySpecClient) { reconfigure(client); nil },
       ->(client : AuthoritySpecClient) { whole_grant(client); nil }}.each do |interrupt|
        client = AuthoritySpecClient.new
        hold_item client
        bot = Rosegold::Bot.new(client)
        done = during_release_wait(client) { bot.use_hand(Rosegold::Look::NORTH); nil }
        interrupt.call(client)
        expect(done.receive).to be_nil
        client.interactions_for_test.tick
        expect(client.frame_ids).not_to contain(use_item_id)
        expect(client.player.look).not_to eq(Rosegold::Look::NORTH)
      end
    end

    it "uses an aimed tap after the release it waited for completes" do
      client = AuthoritySpecClient.new
      hold_item client
      bot = Rosegold::Bot.new(client)
      done = during_release_wait(client) { bot.place_block_against(Rosegold::Vec3i.new(0, 0, 2), BlockFace::Top); nil }
      finish_release client
      expect(done.receive).to be_nil
      client.interactions_for_test.tick
      expect(client.frame_ids).to contain(use_item_id)
    end

    it "does not start an aimed hold when a session reset or a whole grant interrupts its aim" do
      {->(client : AuthoritySpecClient) { reconfigure(client); nil },
       ->(client : AuthoritySpecClient) { whole_grant(client); nil }}.each do |interrupt|
        client = AuthoritySpecClient.new
        bot = Rosegold::Bot.new(client)
        done = during_release_wait(client) { bot.start_digging(Rosegold::Look::NORTH); nil }
        interrupt.call(client)
        expect(done.receive).to be_nil
        expect(client.interactions_for_test.digging?).to be_false
      end
    end

    it "starts an aimed hold after the release it waited for completes" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      done = during_release_wait(client) { bot.start_digging(Rosegold::Look::NORTH); nil }
      finish_release client
      expect(done.receive).to be_nil
      expect(client.interactions_for_test.digging?).to be_true
    end

    it "does not release a later session's hold after its own hold was reset" do
      client = AuthoritySpecClient.new
      bot = DigSpecBot.new(client)
      bot.on_wait = -> do
        reconfigure(client)
        client.interactions_for_test.start_digging
        nil
      end
      bot.dig(1, Rosegold::Look::NORTH)
      expect(client.interactions_for_test.digging?).to be_true
    end

    it "returns true only for a newly queued hold and nil when already held or refused" do
      client = AuthoritySpecClient.new
      bot = DigSpecBot.new(client)
      expect(bot.start_digging(Rosegold::Look::NORTH)).to be_true
      expect(bot.start_digging).to be_nil
      expect(bot.start_digging(Rosegold::Look::SOUTH)).to be_nil
      client.interactions_for_test.stop_digging
      expect(bot.start_digging).to be_true
      client.interactions_for_test.stop_digging
      client.manual_control.grant || fail("grant refused")
      expect(bot.start_digging).to be_nil
      expect(bot.start_digging(Rosegold::Look::NORTH)).to be_nil
      expect(client.interactions_for_test.digging?).to be_false
    end

    it "releases a hold that was already held in the same session when a dig ends" do
      client = AuthoritySpecClient.new
      bot = DigSpecBot.new(client)
      bot.start_digging
      bot.dig(1, Rosegold::Look::NORTH)
      expect(client.interactions_for_test.digging?).to be_false
    end

    it "releases its own hold after an uninterrupted dig or attack" do
      client = AuthoritySpecClient.new
      bot = DigSpecBot.new(client)
      bot.dig(2, Rosegold::Look::NORTH)
      expect(client.interactions_for_test.digging?).to be_false
      bot.attack(Rosegold::Look::SOUTH)
      expect(client.interactions_for_test.digging?).to be_false
    end

    it "does not open a crafting table when a session reset interrupts its aim" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      ran = false
      done = during_release_wait(client) { bot.table_for_test { ran = true }; nil }
      reconfigure(client)
      expect(done.receive).to be_a(Rosegold::Bot::CraftingError)
      expect(ran).to be_false
      expect(bot.opened).to be_nil
      expect(client.frame_ids).to be_empty
    end

    it "opens and closes a crafting table after the release it waited for completes" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      ran = false
      done = during_release_wait(client) { bot.table_for_test { ran = true }; nil }
      finish_release client
      expect(done.receive).to be_nil
      expect(ran).to be_true
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
    end
  end

  describe "opening authority" do
    def operator_chest(client) : Rosegold::ChestMenu
      chest = Rosegold::ChestMenu.new(client, 3_u8, Rosegold::Chat.new("Operator"), 1)
      client.container_menu = chest
      client.emit_event Rosegold::Clientbound::SetContainerContent.new(3_u32, 1_u32,
        [] of Rosegold::WindowSlot, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
      chest
    end

    def hand_back(client)
      client.manual_control.revoke Rosegold::ManualControl::Reason::Returned
      client.release_tick
    end

    it "neither claims nor closes an operator's container after a takeover cancels the opening tap" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      bot = Rosegold::Bot.new(client)
      ran = false
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container(1.second) { ran = true }
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      client.manual_control.grant || fail("grant refused")
      client.interactions_for_test.tick
      chest = operator_chest(client)
      hand_back client

      expect(done.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      expect(ran).to be_false
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::PlayerBlockPlacement))
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::UseItem))
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::CloseWindow))
      expect(client.container_menu.same?(chest)).to be_true
    end

    it "does not claim operator content that arrives during the grant or after the handback" do
      {false, true}.each do |after_handback|
        client = AuthoritySpecClient.new
        client.physics_for_test.unpause_for_spawn_chunk
        bot = OpeningSpecBot.new(client)
        chest = nil.as(Rosegold::ChestMenu?)
        bot.opening = ->(_opener : OpeningSpecBot) do
          client.manual_control.grant
          hand_back client if after_handback
          chest = operator_chest(client)
          hand_back client unless after_handback
          nil
        end
        ran = false
        expect { bot.open_container { ran = true } }.to raise_error(Rosegold::Bot::ContainerOpenError, /interrupted/)
        expect { bot.open_container_handle { |_| ran = true } }.to raise_error(Rosegold::Bot::ContainerOpenError, /interrupted/)
        expect(ran).to be_false
        expect(client.frame_ids).to be_empty
        expect(client.container_menu.same?(chest)).to be_true
      end
    end

    it "does not yield an accepted container when a grant starts before the waiter resumes" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      own = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(opener : OpeningSpecBot) do
        own = opener.open_window(2_u8)
        client.manual_control.grant
        nil
      end
      ran = false
      expect { bot.open_container { ran = true } }.to raise_error(Rosegold::Bot::ContainerOpenError, /interrupted/)
      expect(ran).to be_false
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(own)).to be_true
    end

    it "does not run or clean up a crafting table when the operator opens a menu after a takeover" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      chest = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(_opener : OpeningSpecBot) do
        client.manual_control.grant
        chest = operator_chest(client)
        client.physics_for_test.unpause_for_spawn_chunk
        hand_back client
        client.physics_for_test.pause
        nil
      end
      ran = false
      expect { bot.table_for_test { ran = true } }.to raise_error(Exception, /interrupted/)
      expect(ran).to be_false
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(chest)).to be_true
    end

    it "does not write an opening command that a grant overtakes behind the writer" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      gate = gate_writer(client)
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container_handle("/chest", 200.milliseconds) { |_| fail "no content" }
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      client.manual_control.grant
      gate.send nil
      expect(done.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd)])
    end

    it "leaves its own container to a controller that holds input at cleanup" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.open_container { client.manual_control.grant }
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(bot.opened)).to be_true
    end

    it "does not write a cleanup close that a grant overtakes behind the writer" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      gate = nil.as(Channel(Nil)?)
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container { gate = gate_writer(client) }
        done.send nil
      rescue error
        done.send error
      end
      wait_until { gate }
      sleep 5.milliseconds
      client.manual_control.grant
      gate.try &.send(nil)
      expect(done.receive).to be_nil
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd)])
      expect(client.container_menu.same?(bot.opened)).to be_true
    end

    it "closes its own container after control is handed back during the block" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      bot = OpeningSpecBot.new(client)
      ran = false
      bot.open_container do
        client.manual_control.grant
        hand_back client
        ran = true
      end
      expect(ran).to be_true
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    def left_open_chest(client) : Rosegold::ChestMenu
      client.physics_for_test.unpause_for_spawn_chunk
      client.manual_control.grant || fail("grant refused")
      chest = operator_chest(client)
      hand_back client
      chest
    end

    def resync(client, window_id : UInt32)
      client.emit_event Rosegold::Clientbound::SetContainerContent.new(window_id, 2_u32,
        [] of Rosegold::WindowSlot, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
    end

    it "does not claim a resync of a menu left open when the opening tap has not been dispatched" do
      client = AuthoritySpecClient.new
      chest = left_open_chest(client)
      bot = Rosegold::Bot.new(client)
      ran = false
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container(100.milliseconds) { ran = true }
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      resync client, 3_u32
      expect(done.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      expect(ran).to be_false
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(chest)).to be_true
    end

    it "does not claim a resync of a menu left open while the opening command waits behind the writer" do
      client = AuthoritySpecClient.new
      chest = left_open_chest(client)
      bot = Rosegold::Bot.new(client)
      gate = gate_writer(client)
      ran = false
      done = Channel(Exception?).new(1)
      spawn do
        bot.open_container_handle("/chest", 100.milliseconds) { |_| ran = true }
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      resync client, 3_u32
      gate.send nil
      expect(done.receive).to be_a(Rosegold::Bot::ContainerOpenError)
      expect(ran).to be_false
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd), id(Rosegold::Serverbound::ChatCommand)])
      expect(client.container_menu.same?(chest)).to be_true
    end

    it "claims a new menu that reuses the window id of a menu left open" do
      client = AuthoritySpecClient.new
      chest = left_open_chest(client)
      bot = OpeningSpecBot.new(client)
      fresh = nil.as(Rosegold::ChestMenu?)
      bot.opening = ->(opener : OpeningSpecBot) do
        resync client, 3_u32
        fresh = opener.open_window(3_u8)
        nil
      end
      inside = nil.as(Rosegold::Menu?)
      bot.open_container { inside = client.container_menu }
      expect(inside.same?(fresh)).to be_true
      expect(inside.same?(chest)).to be_false
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end
  end

  describe "pending look" do
    def pending_look(client, &action : -> Nil) : Channel(Nil)
      done = Channel(Nil).new(1)
      spawn do
        action.call
        done.send nil
      end
      wait_until { client.physics_for_test.look_target }
      done
    end

    def finished(done : Channel(Nil)) : Bool
      select
      when done.receive
        true
      when timeout(1.second)
        false
      end
    end

    it "wakes the waiter without applying the look when a reset happens with no grant" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      reconfigure(client)
      expect(finished(done)).to be_true
      expect(client.physics_for_test.look_target).to be_nil
      client.physics_for_test.tick
      expect(client.player.look).to eq(Rosegold::Look::SOUTH)
      expect(client.physics_for_test.last_sent_look).not_to eq(Rosegold::Look::NORTH)
    end

    it "wakes a pending look on reset while another fiber holds the action mutex" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      held = Channel(Nil).new(1)
      release = Channel(Nil).new
      spawn { client.physics_for_test.@action_mutex.synchronize { held.send nil; release.receive } }
      held.receive
      reset = Channel(Nil).new(1)
      spawn do
        reconfigure(client)
        reset.send nil
      end
      expect(finished(reset)).to be_true
      expect(finished(done)).to be_true
      release.send nil
    end

    it "drops an aimed tap whose pending look spans a reset with no grant" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.use_hand(Rosegold::Look::NORTH); nil }
      reconfigure(client)
      expect(finished(done)).to be_true
      client.physics_for_test.tick
      client.interactions_for_test.tick
      expect(client.player.look).to eq(Rosegold::Look::SOUTH)
      expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::UseItem))
    end

    it "applies and completes an ordinary look on the next tick" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      client.physics_for_test.tick
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::NORTH)
      expect(client.physics_for_test.last_sent_look).to eq(Rosegold::Look::NORTH)
      expect(client.frame_payloads).to contain(Rosegold::Serverbound::PlayerLook.new(Rosegold::Look::NORTH, client.player.on_ground?).write)
    end

    def look_frames(client) : Array(Bytes)
      ids = {id(Rosegold::Serverbound::PlayerLook), id(Rosegold::Serverbound::PlayerPositionAndLook)}
      client.frame_payloads.select { |payload| ids.includes?(Minecraft::IO::Memory.new(payload).read_var_int) }
    end

    def stale_look?(client, look : Rosegold::Look) : Bool
      stale = {true, false}.map { |ground| Rosegold::Serverbound::PlayerLook.new(look, ground).write }
      look_frames(client).any? { |payload| stale.includes?(payload) } ||
        client.frame_ids.includes?(id(Rosegold::Serverbound::PlayerPositionAndLook))
    end

    def tick_behind_writer(client, before_tick : -> Nil, &during : -> Nil) : Nil
      gate = gate_writer(client)
      ticked = Channel(Nil).new(1)
      before_tick.call
      spawn do
        client.physics_for_test.tick
        ticked.send nil
      end
      Fiber.yield
      during.call
      gate.send nil
      select
      when ticked.receive
      when timeout(1.second)
        fail "tick did not finish"
      end
    end

    it "does not write a scripted look queued behind a configuration acknowledgment" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      tick_behind_writer(client, -> do
        spawn { Rosegold::Clientbound::StartConfiguration.new.callback(client) }
        Fiber.yield
        nil
      end) { nil }
      wait_until { client.current_protocol_state == Rosegold::ProtocolState::CONFIGURATION }
      ids = client.frame_ids
      expect(ids.first(2)).to eq([id(Rosegold::Serverbound::ClientTickEnd), id(Rosegold::Serverbound::AcknowledgeConfiguration)])
      expect(stale_look?(client, Rosegold::Look::NORTH)).to be_false
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::SOUTH)
      expect(client.physics_for_test.last_sent_look).not_to eq(Rosegold::Look::NORTH)
    end

    it "does not write or commit a scripted look or position frame that a grant overtakes behind the writer" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      client.player.feet = Rosegold::Vec3d.new(3, 0, 3)
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      tick_behind_writer(client, -> { nil }) do
        sleep 5.milliseconds
        client.manual_control.grant || fail("grant refused")
      end
      expect(stale_look?(client, Rosegold::Look::NORTH)).to be_false
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::SOUTH)
      expect(client.physics_for_test.last_sent_look).not_to eq(Rosegold::Look::NORTH)
      client.manual_control.revoke
      client.release_tick
      client.physics_for_test.tick
      expect(stale_look?(client, Rosegold::Look::NORTH)).to be_false
    end

    it "writes a scripted look behind the writer without overwriting a newer local pose" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      tick_behind_writer(client, -> { nil }) do
        sleep 5.milliseconds
        client.player.look = Rosegold::Look::EAST
      end
      expect(stale_look?(client, Rosegold::Look::NORTH)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::EAST)
      expect(client.physics_for_test.last_sent_look).to eq(Rosegold::Look::NORTH)
      expect(client.physics_for_test.look_target).to eq(Rosegold::Look::NORTH)
      client.physics_for_test.tick
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::NORTH)
    end

    def mount(client)
      client.player.entity_id = 300_u64
      vehicle = Rosegold::Entity.new(42_u32, UUID.random, 0_u32, Rosegold::Vec3d.new(0.5, 0, 0.5),
        0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
      client.dimension_for_test.entities[42_u64] = vehicle
      Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(client)
    end

    it "does not write a mounted scripted look that a grant overtakes behind the writer" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      mount client
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      tick_behind_writer(client, -> { nil }) do
        sleep 5.milliseconds
        client.manual_control.grant || fail("grant refused")
      end
      expect(stale_look?(client, Rosegold::Look::NORTH)).to be_false
      expect(look_frames(client)).to contain(Rosegold::Serverbound::PlayerLook.new(Rosegold::Look::SOUTH, false).write)
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::SOUTH)
    end

    it "writes and completes a mounted scripted look" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      client.player.look = Rosegold::Look::SOUTH
      mount client
      bot = Rosegold::Bot.new(client)
      done = pending_look(client) { bot.look = Rosegold::Look::NORTH; nil }
      client.physics_for_test.tick
      expect(finished(done)).to be_true
      expect(client.player.look).to eq(Rosegold::Look::NORTH)
      expect(look_frames(client)).to eq([Rosegold::Serverbound::PlayerLook.new(Rosegold::Look::NORTH, false).write])
    end
  end

  describe "release wait generation" do
    it "refuses a plain scripted write whose release wait spans a session reset" do
      client = AuthoritySpecClient.new
      releasing client
      allowed = Channel(Bool).new(1)
      spawn { allowed.send client.manual_control.script_write_allowed?("probe") }
      sleep 5.milliseconds
      reconfigure(client)
      expect(allowed.receive).to be_false
    end

    it "drops a queued drop when a whole grant starts and releases during its release wait" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      bot = Rosegold::Bot.new(client)
      releasing client
      done = Channel(Nil).new(1)
      spawn do
        bot.drop_hand_single
        done.send nil
      end
      sleep 5.milliseconds
      client.release_tick
      client.manual_control.grant || fail("grant refused")
      client.manual_control.revoke
      client.release_tick
      done.receive
      5.times { Fiber.yield }
      expect(client.frame_ids).to be_empty
    end

    it "sends a queued drop after the release it waited for completes" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      bot = Rosegold::Bot.new(client)
      releasing client
      done = Channel(Nil).new(1)
      spawn do
        bot.drop_hand_single
        done.send nil
      end
      sleep 5.milliseconds
      client.release_tick
      done.receive
      wait_until { client.frame_ids.includes?(id(Rosegold::Serverbound::PlayerAction)) }
    end
  end

  describe "hand mutations across a release wait" do
    it "sends nothing when the PLAY session changes during a queued drop's release wait" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      releasing client
      done = Channel(Nil).new(1)
      spawn do
        bot.drop_hand_single
        done.send nil
      end
      sleep 5.milliseconds
      reconfigure(client)
      done.receive
      5.times { Fiber.yield }
      expect(client.frame_ids).to be_empty
    end

    it "sends nothing when the PLAY session changes during a hand swap's release wait" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
      releasing client
      done = Channel(Exception?).new(1)
      spawn do
        bot.swap_hands(100.milliseconds)
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      reconfigure(client)
      expect(done.receive).to be_nil
      expect(client.frame_ids).to be_empty
    end

    it "lets only one of two hand swaps waiting for the same release run" do
      client = AuthoritySpecClient.new
      client.physics_for_test.unpause_for_spawn_chunk
      bot = Rosegold::Bot.new(client)
      releasing client
      results = Channel(Exception?).new(2)
      2.times do
        spawn do
          bot.swap_hands
          results.send nil
        rescue error
          results.send error
        end
      end
      sleep 5.milliseconds
      client.release_tick
      outcomes = [results.receive, results.receive]
      expect(outcomes.compact.map(&.message)).to eq(["A hand swap is already in progress"])
      expect(client.frame_ids.count(id(Rosegold::Serverbound::PlayerAction))).to eq 1

      bot.swap_hands
      expect(client.frame_ids.count(id(Rosegold::Serverbound::PlayerAction))).to eq 2
    end

    it "does not send or cache the held-slot sync of a swap that loses authority behind the writer" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      client.player.hotbar_selection = 3_u32
      client.inventory_menu[39] = Rosegold::Slot.new(1_u32, 1_u32)
      client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
      gate = gate_writer(client)
      done = Channel(Exception?).new(1)
      spawn do
        bot.swap_hands(100.milliseconds)
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      client.manual_control.grant
      gate.send nil
      expect(done.receive).to be_nil
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd)])
      expect(client.interactions_for_test.@sent_held_item_index).to be_nil
    end

    it "does not swap after a refused close leaves a replacement container open" do
      client = AuthoritySpecClient.new
      bot = Rosegold::Bot.new(client)
      client.inventory_menu[36] = Rosegold::Slot.new(1_u32, 1_u32)
      client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 2_u32)
      client.container_menu = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      replacement = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Other"), 1)
      gate = gate_writer(client)
      done = Channel(Exception?).new(1)
      spawn do
        bot.swap_hands(100.milliseconds)
        done.send nil
      rescue error
        done.send error
      end
      sleep 5.milliseconds
      client.container_menu = replacement
      gate.send nil
      expect(done.receive).to be_nil
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::ClientTickEnd)])
      expect(client.container_menu.same?(replacement)).to be_true
    end
  end

  describe "container cleanup" do
    it "closes the opened container after the block" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.open_container { }
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
      expect(client.container_menu.same?(client.inventory_menu)).to be_true
    end

    it "never closes a replacement opened inside the block" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      replacement = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Other"), 1)
      bot.open_container { client.container_menu = replacement }
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(replacement)).to be_true

      table_replacement = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Other"), 1)
      bot.table_for_test { client.container_menu = table_replacement }
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(table_replacement)).to be_true
    end

    it "still closes the opened container when the cleanup wait raises" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.wait_error = Rosegold::Client::NotConnected.new("lost")
      expect { bot.open_container { } }.to raise_error(Rosegold::Client::NotConnected)
      expect(client.frame_ids).to eq([id(Rosegold::Serverbound::CloseWindow)])
    end

    it "leaves the menu open and propagates an unresolved cancellation untouched" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.wait_error = RuntimeError.new("cleanup wait")
      cancelled = Rosegold::ManualControl::Cancelled.new(Rosegold::ManualControl::Reason::ControllerLost, true)
      expect { bot.open_container { raise cancelled } }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect { bot.open_container_handle { |_| raise cancelled } }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(bot.opened)).to be_true
    end

    it "leaves the menu open when an unresolved cancellation arrives during the cleanup wait" do
      client = AuthoritySpecClient.new
      bot = OpeningSpecBot.new(client)
      bot.wait_error = Rosegold::ManualControl::Cancelled.new(Rosegold::ManualControl::Reason::SessionChanged, true)
      expect { bot.open_container { } }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect { bot.open_container { raise "block failed" } }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect { bot.table_for_test { } }.to raise_error(Rosegold::ManualControl::Cancelled)
      expect(client.frame_ids).to be_empty
      expect(client.container_menu.same?(bot.opened)).to be_true
    end

    it "does not write a queued close after a replacement opens or the session changes" do
      client = AuthoritySpecClient.new
      chest = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Chest"), 1)
      replacement = Rosegold::ChestMenu.new(client, 2_u8, Rosegold::Chat.new("Other"), 1)
      closed = [] of UInt32
      client.on(Rosegold::Event::ContainerClosed) { |event| closed << event.window_id }

      expected_notices = {[] of UInt32, [2_u32]}
      {-> { client.container_menu = replacement; nil },
       -> { reconfigure(client); nil }}.each_with_index do |interrupt, index|
        closed.clear
        client.sink.memory.clear
        client.container_menu = chest
        gate = Channel(Nil).new
        client.sink.gate = gate
        spawn { client.send_packet! Rosegold::Serverbound::ClientTickEnd.new }
        client.sink.entered.receive
        done = Channel(Nil).new(1)
        spawn do
          chest.close
          done.send nil
        end
        sleep 5.milliseconds
        interrupt.call
        gate.send nil
        done.receive
        expect(client.frame_ids).not_to contain(id(Rosegold::Serverbound::CloseWindow))
        expect(closed).to eq(expected_notices[index])
      end
    end
  end
end
