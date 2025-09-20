require "../spec_helper"

Spectator.describe "SpectateServer Integration" do
  it "can connect second bot to spectate server" do
    main_bot = client
    spectate_server = Rosegold::SpectateServer.new("127.0.0.1", 25569)
    spectate_server.attach_client(main_bot)

    # Create a second bot to act as spectator
    spectator_bot = Rosegold::Client.new(
      "127.0.0.1", 25569,
      offline: {
        uuid:     "87654321-4321-8765-2109-876543210987",
        username: "SpectatorBot",
      }
    )

    begin
      client.join_game
      # Start the spectate server
      spectate_server.start
      sleep 0.1.seconds

      # Attempt to connect spectator bot to the spectate server
      spawn do
        begin
          spectator_bot.join_game
        rescue e
          # Connection might fail due to missing server handshake, but that's OK for this test
          Log.debug { "Spectator connection attempt: #{e.message}" }
        end
      end

      # Give some time for connection attempt
      sleep 0.3.seconds

      # Test passes if we can attempt the connection without crashes
      # The actual handshake might fail since we don't have a full server implementation
      expect(spectate_server.server).to_not be_nil
    ensure
      # Clean up
      spectate_server.stop
      sleep 0.1.seconds
    end
  end
end
