require "../spec_helper"

Spectator.describe "SpectateServer Integration" do
  let(spectate_port) { 25569 }

  it "spectator client can connect and receive play packets" do
    main_client = client()

    main_client.join_game do |bot_client|
      Rosegold::Client.protocol_version = bot_client.protocol_version
      bot = Rosegold::Bot.new(bot_client)
      bot.wait_ticks 20 # Ensure physics, inventory, and all systems are fully initialized

      # Verify the bot is fully spawned before starting spectate server
      unless bot_client.spawned?
        fail("Bot not fully spawned after wait_ticks 20")
      end

      # Start spectate server
      spectate_server = Rosegold::SpectateServer.new("127.0.0.1", spectate_port)
      spectate_server.attach_client(bot_client)
      spectate_server.start
      sleep 0.5.seconds # Allow TCP server to fully start accepting connections

      # Connect spectator to SpectateServer
      spectator = Rosegold::Client.new(
        "127.0.0.1", spectate_port,
        offline: {uuid: "11111111-1111-1111-1111-111111111111", username: "SpectatorBot"}
      )

      begin
        spectator.connect

        # Wait until basic play state has arrived
        deadline = Time.instant + 5.seconds
        until (spectator.player.entity_id != 0_u64 && spectator.dimension_for_test.chunks.size > 0) || Time.instant > deadline
          sleep 10.milliseconds
        end

        unless spectator.connected?
          fail("Spectator disconnected: #{spectator.connection?.try(&.close_reason)}")
        end

        # Verify basic play state was received
        expect(spectator.player.entity_id).not_to eq(0_u64)
        expect(spectator.dimension_for_test.chunks.size).to be > 0
      ensure
        spectator.connection?.try(&.disconnect("test done"))
        spectate_server.stop
        sleep 0.2.seconds
      end
    end
  end

  it "spectator connecting before chunks load still ends up spectating with chunks" do
    main_client = client()

    main_client.join_game do |bot_client|
      Rosegold::Client.protocol_version = bot_client.protocol_version
      spectate_server = Rosegold::SpectateServer.new("127.0.0.1", spectate_port)
      spectate_server.attach_client(bot_client)
      spectate_server.start
      sleep 0.5.seconds # Allow TCP server to fully start accepting connections

      spectator = Rosegold::Client.new(
        "127.0.0.1", spectate_port,
        offline: {uuid: "22222222-2222-2222-2222-222222222222", username: "SpectatorBot"}
      )

      begin
        spectator.connect

        # Lobby serves exactly one empty chunk; spectating serves a render-distance square
        deadline = Time.instant + 15.seconds
        until (spectator.player.entity_id != 0_u64 && spectator.dimension_for_test.chunks.size > 1) || Time.instant > deadline
          sleep 10.milliseconds
        end

        unless spectator.connected?
          fail("Spectator disconnected: #{spectator.connection?.try(&.close_reason)}")
        end

        expect(spectator.player.entity_id).not_to eq(0_u64)
        expect(spectator.dimension_for_test.chunks.size).to be > 1
      ensure
        spectator.connection?.try(&.disconnect("test done"))
        spectate_server.stop
        sleep 0.2.seconds
      end
    end
  end

  it "spectator receives complete boss bar states, then remove" do
    main_client = client()

    main_client.join_game do |bot_client|
      Rosegold::Client.protocol_version = bot_client.protocol_version
      bot = Rosegold::Bot.new(bot_client)
      bot.wait_ticks 20
      fail("Bot not fully spawned after wait_ticks 20") unless bot_client.spawned?

      spectate_server = Rosegold::SpectateServer.new("127.0.0.1", spectate_port)
      spectate_server.attach_client(bot_client)
      spectate_server.start
      sleep 0.5.seconds

      spectator = Rosegold::Client.new(
        "127.0.0.1", spectate_port,
        offline: {uuid: "33333333-3333-3333-3333-333333333333", username: "SpectatorBot"}
      )

      begin
        spectator.connect

        deadline = Time.instant + 5.seconds
        until spectate_server.connections.any?(&.boss_bar_session_active?) || Time.instant > deadline
          sleep 10.milliseconds
        end

        unless spectator.connected?
          fail("Spectator disconnected: #{spectator.connection?.try(&.close_reason)}")
        end
        fail("Spectator boss bar session never started") unless spectate_server.connections.any?(&.boss_bar_session_active?)

        boss_events = [] of Rosegold::Clientbound::BossEvent
        spectator.on(Rosegold::Clientbound::BossEvent) { |event| boss_events << event }

        spectate_server.boss_bar("first", 0.5)
        spectate_server.boss_bar("second", 0.7)
        spectate_server.clear_boss_bar

        deadline = Time.instant + 5.seconds
        until boss_events.size >= 3 || Time.instant > deadline
          sleep 10.milliseconds
        end

        actions = boss_events.map(&.action)
        expect(actions).to eq([
          Rosegold::Clientbound::BossEvent::Action::Add,
          Rosegold::Clientbound::BossEvent::Action::Add,
          Rosegold::Clientbound::BossEvent::Action::Remove,
        ])
        expect(boss_events.map(&.uuid).uniq!.size).to eq(1)
      ensure
        spectator.connection?.try(&.disconnect("test done"))
        spectate_server.stop
        sleep 0.2.seconds
      end
    end
  end
end
