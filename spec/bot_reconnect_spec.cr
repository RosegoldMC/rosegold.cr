require "./spec_helper"

class ReconnectSpecClient < Rosegold::Client
  getter transport = Minecraft::IO::Memory.new
  getter join_timeouts = [] of Int32

  def initialize(@join_error : Exception? = nil,
                 authentication_failure : Minecraft::AuthenticationError? = nil,
                 successful_phases : Array(String) = [] of String)
    super("localhost", offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "reconnecttest"})
    @authentication_failure = authentication_failure
    @successful_auth_phases.concat(successful_phases)
    @connection = Rosegold::Connection::Client.new(transport, Rosegold::ProtocolState::PLAY, protocol_version, self)
  end

  def join_game(timeout_ticks = 1200)
    @join_timeouts << timeout_ticks
    if error = @join_error
      raise error
    end
    self
  end
end

class ReconnectSpecBot < Rosegold::Bot
  alias Offline = NamedTuple(uuid: String, username: String)

  @@clients = [] of ReconnectSpecClient
  class_getter delays = [] of Time::Span
  class_getter connection_arguments = [] of {String, Int32, Offline?}

  def self.configure(clients : Array(ReconnectSpecClient))
    @@clients = clients.dup
    @@delays.clear
    @@connection_arguments.clear
  end

  protected def self.build_client(address, port, offline)
    @@connection_arguments << {address, port, offline}
    @@clients.shift? || raise "Unexpected reconnect"
  end

  protected def self.sleep(delay : Time::Span)
    @@delays << delay
  end
end

Spectator.describe "Rosegold::Bot.run" do
  after_each { ReconnectSpecBot.configure([] of ReconnectSpecClient) }

  it "stops after a connected block returns and closes the connection" do
    client = ReconnectSpecClient.new
    ReconnectSpecBot.configure([client])
    calls = 0

    ReconnectSpecBot.run("localhost") { |_bot| calls += 1 }

    expect(calls).to eq(1)
    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
  end

  it "rejoins with a fresh bot and client and forwards connection options" do
    first = ReconnectSpecClient.new
    second = ReconnectSpecClient.new
    ReconnectSpecBot.configure([first, second])
    bots = [] of ReconnectSpecBot
    offline = {uuid: "00000000-0000-0000-0000-000000000000", username: "reconnecttest"}

    ReconnectSpecBot.run("example.invalid", 25570, offline: offline, timeout_ticks: 42) do |bot|
      bots << bot
      if bots.size == 1
        bot.auto_respawn = false
        bot.client.disconnect("Server closed the session")
      end
    end

    expect(bots.size).to eq(2)
    expect(bots.first).not_to be(bots.last)
    expect(bots.map(&.client)).to eq([first, second])
    expect(bots.last.auto_respawn?).to be_true
    expect(first.join_timeouts).to eq([42])
    expect(second.join_timeouts).to eq([42])
    expect(ReconnectSpecBot.connection_arguments).to eq([
      {"example.invalid", 25570, offline}, {"example.invalid", 25570, offline},
    ])
    expect(ReconnectSpecBot.delays).to eq([10.seconds])
    expect(first.transport.closed?).to be_true
    expect(second.transport.closed?).to be_true
  end

  it "stops when the script explicitly disconnects" do
    client = ReconnectSpecClient.new
    ReconnectSpecBot.configure([client])

    ReconnectSpecBot.run("localhost", &.disconnect("Finished"))

    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
    expect(client.connection?.try(&.close_reason).try(&.to_s)).to eq("Finished")
  end

  it "stops if an operation notices an explicit script disconnect" do
    client = ReconnectSpecClient.new
    ReconnectSpecBot.configure([client])

    ReconnectSpecBot.run("localhost") do |bot|
      bot.disconnect("Finished")
      raise Rosegold::Client::NotConnected.new("Disconnected")
    end

    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
  end

  it "retries joining after network and NotConnected errors and closes each attempt" do
    errors = [
      Rosegold::Client::NotConnected.new("Join timed out"),
      IO::Error.new("Connection reset"),
      Socket::Error.new("Connection refused"),
    ]
    errors.each do |error|
      first = ReconnectSpecClient.new(error)
      second = ReconnectSpecClient.new
      ReconnectSpecBot.configure([first, second])
      bots = [] of ReconnectSpecBot

      ReconnectSpecBot.run("localhost") { |bot| bots << bot }

      expect(bots.map(&.client)).to eq([second])
      expect(ReconnectSpecBot.delays).to eq([10.seconds])
      expect(first.transport.closed?).to be_true
      expect(second.transport.closed?).to be_true
    end
  end

  it "retries network errors raised by the running script" do
    first = ReconnectSpecClient.new
    second = ReconnectSpecClient.new
    ReconnectSpecBot.configure([first, second])
    calls = 0

    ReconnectSpecBot.run("localhost") do |_bot|
      calls += 1
      raise IO::Error.new("Connection reset") if calls == 1
    end

    expect(calls).to eq(2)
    expect(ReconnectSpecBot.delays).to eq([10.seconds])
    expect(first.transport.closed?).to be_true
    expect(second.transport.closed?).to be_true
  end

  it "propagates script errors after closing the connection" do
    client = ReconnectSpecClient.new
    ReconnectSpecBot.configure([client])

    expect do
      ReconnectSpecBot.run("localhost") { |_bot| raise ArgumentError.new("Script failed") }
    end.to raise_error(ArgumentError, "Script failed")

    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
  end

  it "propagates a missing script file instead of reconnecting" do
    client = ReconnectSpecClient.new
    ReconnectSpecBot.configure([client])
    missing_path = File.join(Dir.tempdir, "rosegold-reconnect-missing-#{UUID.random}")

    expect do
      ReconnectSpecBot.run("localhost") { |_bot| File.read(missing_path) }
    end.to raise_error(File::NotFoundError)

    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
  end

  it "propagates permanent interactive Microsoft authentication failures" do
    error = Minecraft::AuthenticationError.new("Sign-in declined", phase: "microsoft_device")
    client = ReconnectSpecClient.new(error)
    ReconnectSpecBot.configure([client])

    expect do
      ReconnectSpecBot.run("localhost") { |_bot| raise "Must not run before joining" }
    end.to raise_error(Minecraft::AuthenticationError, "Sign-in declined")

    expect(ReconnectSpecBot.delays).to be_empty
    expect(client.transport.closed?).to be_true
  end

  it "retries transient interactive Microsoft authentication failures" do
    error = Minecraft::AuthenticationError.new("Unavailable", phase: "microsoft_device", transient: true)
    first = ReconnectSpecClient.new(error)
    second = ReconnectSpecClient.new
    ReconnectSpecBot.configure([first, second])

    ReconnectSpecBot.run("localhost") { |_bot| }

    expect(ReconnectSpecBot.delays).to eq([1.minute])
    expect(first.transport.closed?).to be_true
    expect(second.transport.closed?).to be_true
  end

  it "honors authentication failures reported by the packet reader" do
    error = Minecraft::AuthenticationError.new("Rate limited", phase: "session_join", status_code: 429, retry_after: 1.hour)
    first = ReconnectSpecClient.new(Rosegold::Client::NotConnected.new("Reader stopped"), authentication_failure: error)
    second = ReconnectSpecClient.new
    ReconnectSpecBot.configure([first, second])

    ReconnectSpecBot.run("localhost") { |_bot| }

    expect(ReconnectSpecBot.delays).to eq([1.hour])
    expect(first.transport.closed?).to be_true
    expect(second.transport.closed?).to be_true
  end

  it "preserves a failed phase streak when earlier authentication phases succeed" do
    error = Minecraft::AuthenticationError.new("Forbidden", phase: "xsts", status_code: 403)
    clients = Array.new(3) { ReconnectSpecClient.new(error, successful_phases: ["xbox_live"]) }
    clients << ReconnectSpecClient.new
    ReconnectSpecBot.configure(clients)

    ReconnectSpecBot.run("localhost") { |_bot| }

    expect(ReconnectSpecBot.delays).to eq([5.minutes, 10.minutes, 15.minutes])
    expect(clients.all?(&.transport.closed?)).to be_true
  end

  it "clears a phase streak after that phase succeeds in a later attempt" do
    xbox = Minecraft::AuthenticationError.new("Forbidden", phase: "xbox_live", status_code: 403)
    xsts = Minecraft::AuthenticationError.new("Forbidden", phase: "xsts", status_code: 403)
    clients = [
      ReconnectSpecClient.new(xbox),
      ReconnectSpecClient.new(xbox),
      ReconnectSpecClient.new(xsts, successful_phases: ["xbox_live"]),
      ReconnectSpecClient.new(xbox),
      ReconnectSpecClient.new,
    ]
    ReconnectSpecBot.configure(clients)

    ReconnectSpecBot.run("localhost") { |_bot| }

    expect(ReconnectSpecBot.delays).to eq([5.minutes, 10.minutes, 5.minutes, 5.minutes])
    expect(clients.all?(&.transport.closed?)).to be_true
  end

  it "clears a session-join cooldown only after a successful session join" do
    join = Minecraft::AuthenticationError.new("Forbidden", phase: "session_join", status_code: 403)
    clients = [
      ReconnectSpecClient.new(join),
      ReconnectSpecClient.new(join),
      ReconnectSpecClient.new(successful_phases: ["session_join"]),
      ReconnectSpecClient.new(join),
      ReconnectSpecClient.new,
    ]
    ReconnectSpecBot.configure(clients)

    ReconnectSpecBot.run("localhost") do |bot|
      bot.client.disconnect("Server closed the session") if bot.client == clients[2]
    end

    expect(ReconnectSpecBot.delays).to eq([5.minutes, 10.minutes, 10.seconds, 5.minutes])
    expect(clients.all?(&.transport.closed?)).to be_true
  end

  it "quickly retries a rejected cached token before cooling down a fresh-token rejection" do
    cached = Minecraft::AuthenticationError.new("Cached token rejected", phase: "session_join", status_code: 403,
      refresh_cached_token: true)
    fresh = Minecraft::AuthenticationError.new("Fresh token rejected", phase: "session_join", status_code: 403)
    clients = [ReconnectSpecClient.new(cached), ReconnectSpecClient.new(fresh), ReconnectSpecClient.new]
    ReconnectSpecBot.configure(clients)

    ReconnectSpecBot.run("localhost") { |_bot| }

    expect(ReconnectSpecBot.delays).to eq([10.seconds, 5.minutes])
    expect(clients.all?(&.transport.closed?)).to be_true
  end
end
