require "./spec_helper"

class GuardedChatSpecSink < ::IO
  getter memory = ::IO::Memory.new
  property gate : Channel(Nil)?
  property? fail = false
  getter entered = Channel(Nil).new(1)

  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
    raise ::IO::Error.new("boom") if fail?
    if gate = @gate
      @gate = nil
      entered.send(nil)
      gate.receive
    end
    memory.write slice
  end
end

class GuardedChatSpecClient < Rosegold::Client
  getter sink = GuardedChatSpecSink.new

  def initialize
    super("localhost", offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "guardedchat"})
    @connection = Rosegold::Connection::Client.new(Minecraft::IO::Wrap.new(sink), Rosegold::ProtocolState::PLAY, protocol_version, self)
    set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def chat_frames : Array(Rosegold::Serverbound::ChatMessage)
    io = Minecraft::IO::Memory.new(sink.memory.to_slice.dup)
    frames = [] of Rosegold::Serverbound::ChatMessage
    while io.pos < io.size
      payload = Bytes.new(io.read_var_int)
      io.read_fully(payload)
      packet = Rosegold::Connection::Client.decode_serverbound_packet(payload, Rosegold::ProtocolState::PLAY, protocol_version)
      frames << packet if packet.is_a?(Rosegold::Serverbound::ChatMessage)
    end
    frames
  end

  def index : UInt32
    chat_manager.@message_index
  end
end

Spectator.describe "guarded chat send" do
  let(client) { GuardedChatSpecClient.new }

  it "refuses without writing or advancing state when the guard declines" do
    result = client.chat_manager.try_send_message("hello") { false }
    expect(result).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq 0
    expect(client.index).to eq 0_u32
  end

  it "does not deliver while contended or after a revoked lease, then a valid send succeeds" do
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      done.send(nil)
    end
    client.sink.entered.receive
    size_before = client.sink.memory.size

    busy = client.chat_manager.try_send_message("stale") { true }
    expect(busy).to eq Rosegold::SendResult::Busy
    expect(client.index).to eq 0_u32

    gate.send(nil)
    done.receive
    after_ordinary = client.sink.memory.size
    expect(after_ordinary).to be > size_before

    lease = true
    lease = false
    revoked = client.chat_manager.try_send_message("stale") { lease }
    expect(revoked).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq after_ordinary
    expect(client.index).to eq 0_u32

    lease = true
    sent = client.chat_manager.try_send_message("fresh") { lease }
    expect(sent).to eq Rosegold::SendResult::Sent
    expect(client.sink.memory.size).to be > after_ordinary
    expect(client.index).to eq 1_u32
    expect(String.new(client.sink.memory.to_slice)).to_not contain("stale")
  end

  it "refuses invalid text and commands" do
    ["", "/op me", "a\nb", "x" * 257].each do |text|
      expect(client.chat_manager.try_send_message(text) { true }).to eq Rosegold::SendResult::Refused
    end
    expect(client.sink.memory.size).to eq 0
  end

  it "refuses outside PLAY" do
    client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
    expect(client.chat_manager.try_send_message("hi") { true }).to eq Rosegold::SendResult::Refused
  end

  it "refuses without disconnecting when the guard raises" do
    result = client.chat_manager.try_send_message("boom") { raise "guard failed" }
    expect(result).to eq Rosegold::SendResult::Refused
    expect(client.connection.open?).to be_true
    expect(client.sink.memory.size).to eq 0
    expect(client.chat_manager.try_send_message("ok") { true }).to eq Rosegold::SendResult::Sent
  end

  it "rechecks connection and PLAY state after a yielding or state-changing guard" do
    changed = client.chat_manager.try_send_message("moved") do
      Fiber.yield
      client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
      true
    end
    expect(changed).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq 0
    expect(client.index).to eq 0_u32

    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    conn = client.connection
    swapped = client.chat_manager.try_send_message("closed") do
      conn.disconnect("test")
      true
    end
    expect(swapped).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq 0
  end

  it "sends a guarded slash command once through ChatCommand" do
    expect(client.chat_manager.try_send_command("/list") { true }).to eq Rosegold::SendResult::Sent
    expect(String.new(client.sink.memory.to_slice)).to contain("list")
    expect(client.index).to eq 0_u32
  end

  it "keeps a second leading slash for commands like //wand" do
    expect(client.chat_manager.try_send_command("//wand") { true }).to eq Rosegold::SendResult::Sent
    expect(String.new(client.sink.memory.to_slice)).to contain("/wand")
  end

  it "refuses invalid commands, a declining guard, and a raising guard without writing" do
    ["", "/", "/  ", "list", "/a\nb", "/" + "x" * 257, "/a§b"].each do |text|
      expect(client.chat_manager.try_send_command(text) { true }).to eq Rosegold::SendResult::Refused
    end
    expect(client.chat_manager.try_send_command("/list") { false }).to eq Rosegold::SendResult::Refused
    expect(client.chat_manager.try_send_command("/list") { raise "guard" }).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq 0
    expect(client.connection.open?).to be_true
  end

  it "builds vanilla last-seen acknowledgments: newest signature is bit 19, offsets and checksum match" do
    manager = client.chat_manager
    first = Bytes.new(256, 1_u8)
    second = Bytes.new(256, &.to_u8)

    empty = manager.acknowledgment
    expect({empty.offset, empty.bitset.to_a, empty.checksum}).to eq({0_u32, [0_u8, 0_u8, 0_u8], 1_u8})

    manager.add_last_seen_signature(first)
    manager.add_last_seen_signature(first)
    one = manager.acknowledgment
    expect({one.offset, one.bitset.to_a, one.checksum}).to eq({1_u32, [0_u8, 0_u8, 0x08_u8], 32_u8})

    manager.add_last_seen_signature(second)
    two = manager.acknowledgment
    expect({two.offset, two.bitset.to_a, two.checksum}).to eq({2_u32, [0_u8, 0_u8, 0x0c_u8], 97_u8})
  end

  it "consumes only the offset it sent, keeps the window, and ignores unsigned traffic" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    expect(manager.try_send_message("one") { true }).to eq Rosegold::SendResult::Sent
    expect(manager.acknowledgment.offset).to eq 0_u32
    expect(manager.acknowledgment.bitset.to_a).to eq [0_u8, 0_u8, 0x08_u8]
    expect(manager.try_send_command("/list") { true }).to eq Rosegold::SendResult::Sent
    manager.add_last_seen_signature(Bytes.new(256, 2_u8))
    expect(manager.acknowledgment.offset).to eq 1_u32
    expect(manager.try_send_message("two") { true }).to eq Rosegold::SendResult::Sent
    expect(manager.acknowledgment.offset).to eq 0_u32
  end

  it "refuses a send whose acknowledgment went stale while writing, and resets on a new session" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    result = manager.try_send_message("stale") do
      manager.add_last_seen_signature(Bytes.new(256, 2_u8))
      true
    end
    expect(result).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq 0
    expect(manager.acknowledgment.offset).to eq 2_u32
    manager.reset_session
    expect(manager.acknowledgment.offset).to eq 0_u32
    expect(manager.acknowledgment.bitset.to_a).to eq [0_u8, 0_u8, 0_u8]
  end

  it "never puts the same last-seen offset on two chat frames when sends overlap at the writer" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      manager.send_message("first")
      done.send(nil)
    end
    client.sink.entered.receive
    spawn do
      manager.send_message("second")
      done.send(nil)
    end
    Fiber.yield
    gate.send(nil)
    2.times { done.receive }

    frames = client.chat_frames
    expect(frames.map(&.message)).to eq ["first", "second"]
    expect(frames.map(&.message_count)).to eq [1_u32, 0_u32]
    expect(frames.map(&.acknowledged.to_a)).to eq [[0_u8, 0_u8, 0x08_u8], [0_u8, 0_u8, 0x08_u8]]
  end

  it "builds an ordinary chat frame after an in-flight guarded send commits" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      manager.try_send_message("guarded") { true }
      done.send(nil)
    end
    client.sink.entered.receive
    spawn do
      manager.send_message("ordinary")
      done.send(nil)
    end
    Fiber.yield
    gate.send(nil)
    2.times { done.receive }

    expect(client.chat_frames.map(&.message_count)).to eq [1_u32, 0_u32]
  end

  it "reports a failed write without advancing the message index or retrying" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    client.sink.fail = true
    expect(manager.send_message("lost")).to be_false
    expect(client.index).to eq 0_u32
    expect(client.sink.memory.size).to eq 0
  end

  it "commits a guarded send under the write lock so a queued ordinary send sees the new offset" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      manager.try_send_message("guarded") { true }
      done.send(nil)
    end
    client.sink.entered.receive
    spawn do
      manager.send_message("ordinary")
      done.send(nil)
    end
    Fiber.yield
    expect(client.index).to eq 0_u32
    gate.send(nil)
    2.times { done.receive }
    expect(client.chat_frames.map(&.message_count)).to eq [1_u32, 0_u32]
    expect(client.index).to eq 2_u32
  end

  it "does not commit a guarded send whose write fails or whose guard declines" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    expect(manager.try_send_message("no") { false }).to eq Rosegold::SendResult::Refused
    expect(manager.acknowledgment.offset).to eq 1_u32
    client.sink.fail = true
    expect { manager.try_send_message("boom") { true } }.to raise_error(IO::Error)
    expect(client.index).to eq 0_u32
  end

  it "keeps the connection open when the packet builder raises" do
    conn = client.connection
    expect { conn.send_packet(-> : Bytes { raise "build" }, -> : Nil { }, -> { true }) }.to raise_error(Exception, "build")
    expect(conn.open?).to be_true
    expect(client.sink.memory.size).to eq 0
  end

  it "writes no chat frame after AcknowledgeConfiguration even when queued behind it" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      done.send(nil)
    end
    client.sink.entered.receive
    spawn do
      Rosegold::Clientbound::StartConfiguration.new.callback(client)
      done.send(nil)
    end
    Fiber.yield
    result = nil
    spawn do
      result = manager.send_message("late")
      done.send(nil)
    end
    Fiber.yield
    gate.send(nil)
    3.times { done.receive }

    expect(result).to be_false
    expect(client.chat_frames).to be_empty
    expect(client.index).to eq 0_u32
    expect(client.current_protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
    expect(client.connection.open?).to be_true
  end

  it "writes no chat frame in the window between the acknowledgment and the state change" do
    manager = client.chat_manager
    manager.add_last_seen_signature(Bytes.new(256, 1_u8))
    client.connection.send_packet Rosegold::Serverbound::AcknowledgeConfiguration.new
    size = client.sink.memory.size
    expect(client.current_protocol_state).to eq Rosegold::ProtocolState::PLAY

    expect(manager.send_message("late")).to be_false
    expect(manager.try_send_message("late") { true }).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq size
    expect(client.index).to eq 0_u32
    expect(manager.acknowledgment.offset).to eq 1_u32
    expect(client.connection.open?).to be_true
  end

  it "refuses writes queued across a reconfiguration and sends again once PLAY returns" do
    manager = client.chat_manager
    gate = Channel(Nil).new
    client.sink.gate = gate
    done = Channel(Nil).new
    spawn do
      client.send_packet! Rosegold::Serverbound::ClientTickEnd.new
      done.send(nil)
    end
    client.sink.entered.receive
    spawn do
      Rosegold::Clientbound::StartConfiguration.new.callback(client)
      done.send(nil)
    end
    Fiber.yield
    old = [] of String
    spawn do
      old << manager.send_message("old").to_s
      old << manager.try_send_message("old guarded") { true }.to_s
      old << manager.try_send_command("/old") { true }.to_s
      done.send(nil)
    end
    Fiber.yield
    gate.send(nil)
    3.times { done.receive }

    expect(old).to eq ["false", "Refused", "Refused"]
    expect(client.current_protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
    size = client.sink.memory.size
    expect(manager.try_send_command("/cfg") { true }).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq size

    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    expect(manager.send_message("fresh")).to be_true
    expect(manager.try_send_message("fresh guarded") { true }).to eq Rosegold::SendResult::Sent
    expect(manager.try_send_command("/fresh") { true }).to eq Rosegold::SendResult::Sent
    expect(client.chat_frames.map(&.message)).to eq ["fresh", "fresh guarded"]
    expect(String.new(client.sink.memory.to_slice)).to contain("fresh")
    expect(String.new(client.sink.memory.to_slice)).to_not contain("old")
    expect(client.connection.open?).to be_true
  end

  it "refuses the command path between the acknowledgment and the state change" do
    client.connection.send_packet Rosegold::Serverbound::AcknowledgeConfiguration.new
    size = client.sink.memory.size
    expect(client.chat_manager.try_send_command("/late") { true }).to eq Rosegold::SendResult::Refused
    expect(client.sink.memory.size).to eq size
  end
end
