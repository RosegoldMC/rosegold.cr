require "../spec_helper"

Spectator.describe "SpectateServer Integration" do
  let(spectate_port) { 25569 }

  it "spectator client can connect and receive play packets" do
    main_client = client()
    Rosegold::Client.protocol_version = main_client.protocol_version

    main_client.join_game do |bot_client|
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
end
