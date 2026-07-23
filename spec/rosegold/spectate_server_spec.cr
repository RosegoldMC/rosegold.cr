require "../spec_helper"

Spectator.describe Rosegold::Spectate::Server do
  after_each { Rosegold::Client.reset_protocol_version! }

  def fake_spectator(server, active = true)
    tcp = TCPServer.new("127.0.0.1", 0)
    spectator_socket = TCPSocket.new("127.0.0.1", tcp.local_address.port)
    spectator_socket.read_timeout = 1.second
    connection = Rosegold::Spectate::Connection.new(tcp.accept, server)
    connection.spectate_state = Rosegold::Spectate::State::SPECTATING
    session = active ? connection.begin_boss_bar_session : 0_u64
    server.connections << connection
    {connection, spectator_socket, tcp, session}
  end

  def read_boss_event(socket) : Rosegold::Clientbound::BossEvent
    io = Minecraft::IO::Wrap.new(socket)
    size = io.read_var_int
    bytes = Bytes.new(size)
    io.read_fully(bytes)
    packet_io = Minecraft::IO::Memory.new(bytes)
    packet_io.read_byte
    Rosegold::Clientbound::BossEvent.read(packet_io)
  end

  def offline_client : Rosegold::Client
    Rosegold::Client.new("127.0.0.1", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "Bot"})
  end

  def emit_boss_event(client, event)
    event.callback(client)
    client.emit_event(event)
  end

  it "does not raw-forward boss_event on any protocol" do
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      forwarded = Rosegold::Spectate::Server.forwarded_packets(protocol)
      expect(forwarded.has_key?(Rosegold::Clientbound::BossEvent[protocol])).to be_false
    end
  end

  it "sends complete add state on every boss_bar call" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    connection, socket, tcp, _session = fake_spectator(server)

    server.boss_bar("hello", 0.5)
    server.boss_bar("hello", 0.7)

    add = read_boss_event(socket)
    expect(add.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
    expect(add.title.try(&.to_s)).to eq("hello")

    replacement = read_boss_event(socket)
    expect(replacement.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
    expect(replacement.health).to be_close(0.7_f32, 1e-6)
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  it "replaces a boss bar when only title formatting changes" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    connection, socket, tcp, _session = fake_spectator(server)
    first = Rosegold::TextComponent.new("hello")
    second = Rosegold::TextComponent.new("hello")
    second.color = "red"

    server.boss_bar(first, 0.5)
    server.boss_bar(second, 0.5)

    expect(read_boss_event(socket).action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
    replacement = read_boss_event(socket)
    expect(replacement.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
    expect(replacement.title.try(&.color)).to eq("red")
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  it "sends only complete state during concurrent boss_bar calls" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    connection, socket, tcp, _session = fake_spectator(server)
    done = Channel(Nil).new

    100.times do |i|
      spawn do
        server.boss_bar("bar #{i}", i / 100.0)
        done.send(nil)
      end
    end
    100.times { done.receive }

    events = Array(Rosegold::Clientbound::BossEvent).new(100) { read_boss_event(socket) }
    expect(events.all?(&.action.add?)).to be_true
    expect(events.map(&.uuid).uniq!.size).to eq(1)
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  it "does not send boss bars before a spectator session starts" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    connection, socket, tcp, _session = fake_spectator(server, active: false)
    socket.read_timeout = 0.2.seconds

    server.boss_bar("hello", 0.5)

    expect_raises(IO::TimeoutError) { read_boss_event(socket) }
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  it "sends latest state before replay" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    server.boss_bar("hello", 0.5)
    connection, socket, tcp, _session = fake_spectator(server)

    server.boss_bar("hello", 0.7)

    add = read_boss_event(socket)
    expect(add.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
    expect(add.health).to be_close(0.7_f32, 1e-6)
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  describe "upstream boss bars" do
    it "relays complete state and remove for bars the upstream server added" do
      Rosegold::Client.protocol_version = 774_u32
      server = Rosegold::Spectate::Server.new
      client = offline_client
      server.attach_client(client)
      connection, socket, tcp, _session = fake_spectator(server)

      uuid = UUID.random
      title = Rosegold::TextComponent.new("Wither")

      emit_boss_event(client, Rosegold::Clientbound::BossEvent.add(uuid, title, 1.0_f32, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::None))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_title(uuid, Rosegold::TextComponent.new("Angry Wither")))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_health(uuid, 0.5_f32))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.remove(uuid))

      expect(read_boss_event(socket).action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      title_replacement = read_boss_event(socket)
      expect(title_replacement.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      expect(title_replacement.title.try(&.to_s)).to eq("Angry Wither")
      health_replacement = read_boss_event(socket)
      expect(health_replacement.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      expect(health_replacement.health).to be_close(0.5_f32, 1e-6)
      expect(read_boss_event(socket).action).to eq(Rosegold::Clientbound::BossEvent::Action::Remove)
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end

    it "drops updates for bars the client never saw an add for" do
      Rosegold::Client.protocol_version = 774_u32
      server = Rosegold::Spectate::Server.new
      client = offline_client
      server.attach_client(client)
      connection, socket, tcp, _session = fake_spectator(server)
      socket.read_timeout = 0.2.seconds

      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_health(UUID.random, 0.5_f32))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.remove(UUID.random))

      expect_raises(IO::TimeoutError) { read_boss_event(socket) }
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end

    it "replays current state when add and updates arrived before attachment" do
      Rosegold::Client.protocol_version = 774_u32
      client = offline_client
      uuid = UUID.random

      emit_boss_event(client, Rosegold::Clientbound::BossEvent.add(uuid, Rosegold::TextComponent.new("Wither"), 1.0_f32, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::None))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_health(uuid, 0.4_f32))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_title(uuid, Rosegold::TextComponent.new("Angry Wither")))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_style(uuid, Rosegold::Clientbound::BossEvent::Color::Red, Rosegold::Clientbound::BossEvent::Division::Notches10))
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_flags(uuid, 0x03_u8))

      server = Rosegold::Spectate::Server.new
      server.attach_client(client)
      connection, socket, tcp, session = fake_spectator(server)
      server.replay_ui_state(connection, session)

      add = read_boss_event(socket)
      expect(add.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      expect(add.uuid).to eq(uuid)
      expect(add.title.try(&.to_s)).to eq("Angry Wither")
      expect(add.health).to be_close(0.4_f32, 1e-6)
      expect(add.color).to eq(Rosegold::Clientbound::BossEvent::Color::Red)
      expect(add.division).to eq(Rosegold::Clientbound::BossEvent::Division::Notches10)
      expect(add.flags).to eq(0x03_u8)
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end

    it "sends an add when an upstream update arrives before replay" do
      Rosegold::Client.protocol_version = 774_u32
      client = offline_client
      uuid = UUID.random
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.add(uuid, Rosegold::TextComponent.new("Wither"), 1.0_f32, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::None))

      server = Rosegold::Spectate::Server.new
      server.attach_client(client)
      connection, socket, tcp, _session = fake_spectator(server)

      emit_boss_event(client, Rosegold::Clientbound::BossEvent.update_health(uuid, 0.5_f32))

      add = read_boss_event(socket)
      expect(add.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      expect(add.uuid).to eq(uuid)
      expect(add.health).to be_close(0.5_f32, 1e-6)
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end

    it "removes bars from a replaced client" do
      Rosegold::Client.protocol_version = 774_u32
      first_client = offline_client
      uuid = UUID.random
      emit_boss_event(first_client, Rosegold::Clientbound::BossEvent.add(uuid, Rosegold::TextComponent.new("Old Wither"), 1.0_f32, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::None))

      server = Rosegold::Spectate::Server.new
      server.attach_client(first_client)
      connection, socket, tcp, session = fake_spectator(server)
      server.replay_ui_state(connection, session)
      expect(read_boss_event(socket).action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)

      server.attach_client(offline_client)

      remove = read_boss_event(socket)
      expect(remove.action).to eq(Rosegold::Clientbound::BossEvent::Action::Remove)
      expect(remove.uuid).to eq(uuid)
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end

    it "removes cached bars when the client starts configuration" do
      Rosegold::Client.protocol_version = 774_u32
      client = offline_client
      uuid = UUID.random
      emit_boss_event(client, Rosegold::Clientbound::BossEvent.add(uuid, Rosegold::TextComponent.new("Wither"), 1.0_f32, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::None))

      server = Rosegold::Spectate::Server.new
      server.attach_client(client)
      connection, socket, tcp, session = fake_spectator(server)
      server.replay_ui_state(connection, session)
      expect(read_boss_event(socket).action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)

      client.clear_boss_bars
      client.emit_event(Rosegold::Clientbound::StartConfiguration.new)

      remove = read_boss_event(socket)
      expect(remove.action).to eq(Rosegold::Clientbound::BossEvent::Action::Remove)
      expect(remove.uuid).to eq(uuid)
    ensure
      connection.try(&.close)
      socket.try(&.close)
      tcp.try(&.close)
    end
  end

  it "removes known bars before ending a spectator session" do
    Rosegold::Client.protocol_version = 774_u32
    server = Rosegold::Spectate::Server.new
    connection, socket, tcp, _session = fake_spectator(server)

    server.boss_bar("own", 0.5)
    add = read_boss_event(socket)
    connection.spectate_state = Rosegold::Spectate::State::LOBBY
    connection.end_boss_bar_session

    remove = read_boss_event(socket)
    expect(remove.action).to eq(Rosegold::Clientbound::BossEvent::Action::Remove)
    expect(remove.uuid).to eq(add.uuid)
  ensure
    connection.try(&.close)
    socket.try(&.close)
    tcp.try(&.close)
  end

  it "unsubscribes from client events when stopped" do
    client = offline_client
    before = client.event_handlers[Rosegold::Clientbound::BossEvent]?.try(&.size) || 0
    server = Rosegold::Spectate::Server.new
    server.attach_client(client)

    expect(client.event_handlers[Rosegold::Clientbound::BossEvent].size).to eq(before + 1)

    server.stop

    expect(client.event_handlers[Rosegold::Clientbound::BossEvent].size).to eq(before)
  end
end
