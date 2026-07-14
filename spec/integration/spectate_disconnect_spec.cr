require "../spec_helper"

Spectator.describe "SpectateServer bot disconnect" do
  let(spectate_port) { 25571 }

  def wait_until(timeout : Time::Span, &) : Bool
    deadline = Time.instant + timeout
    until (yield) || Time.instant > deadline
      sleep 20.milliseconds
    end
    Time.instant <= deadline
  end

  # A spectator connected before the bot drops must survive the transition to lobby,
  # receive the lobby chat, and stay connected across a reconnect/disconnect flap.
  it "keeps the spectator connected and in lobby when the bot disconnects" do
    bot1 = client()
    bot1.join_game
    Rosegold::Client.protocol_version = bot1.protocol_version

    spectate_server = Rosegold::SpectateServer.new("127.0.0.1", spectate_port)
    spectate_server.attach_client(bot1)
    spectate_server.start
    sleep 0.5.seconds

    spectator = Rosegold::Client.new(
      "127.0.0.1", spectate_port,
      offline: {uuid: "33333333-3333-3333-3333-333333333333", username: "SpectatorBot"}
    )

    lobby_messages = 0
    spectator.on(Rosegold::Clientbound::SystemChatMessage) do |e|
      lobby_messages += 1 if e.message.to_s.includes?("disconnected")
    end

    current_bot = bot1
    begin
      spectator.connect
      fail("spectator never started spectating") unless wait_until(15.seconds) { spectator.dimension_for_test.chunks.size > 1 }

      admin.chat "/kick #{AdminBot::TEST_PLAYER}"
      fail("no lobby chat after bot disconnect") unless wait_until(10.seconds) { lobby_messages >= 1 }
      fail("spectator dropped on bot disconnect: #{spectator.connection?.try(&.close_reason)}") unless spectator.connected?

      bot2 = client()
      bot2.join_game
      spectate_server.attach_client(bot2)
      current_bot = bot2
      fail("spectator never re-entered spectating") unless wait_until(15.seconds) { spectator.dimension_for_test.chunks.size > 1 }

      admin.chat "/kick #{AdminBot::TEST_PLAYER}"
      fail("no lobby chat after 2nd disconnect") unless wait_until(10.seconds) { lobby_messages >= 2 }

      # Survive a full keep-alive interval in lobby without the server closing the socket.
      wait_until(25.seconds) { !spectator.connected? }
      fail("spectator disconnected in lobby: #{spectator.connection?.try(&.close_reason)}") unless spectator.connected?

      expect(spectator.connected?).to be_true
      expect(lobby_messages).to be >= 2
    ensure
      spectator.connection?.try(&.disconnect("test done"))
      spectate_server.stop
      current_bot.connection?.try(&.disconnect("done"))
      sleep 0.3.seconds
    end
  end
end
