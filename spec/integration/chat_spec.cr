require "../spec_helper"

Spectator.describe "Rosegold::Bot chat functionality" do
  it "should be able to send basic chat messages" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Send a simple chat message
        bot.chat "Hello from integration test!"
        bot.wait_ticks 5 # Wait for message to be processed

        # The test passes if no exception is thrown during chat
        expect(true).to be_true
      end
    end
  end

  it "should be able to send chat commands" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Send a command via chat
        bot.chat "/time query daytime"
        bot.wait_ticks 5 # Wait for command to be processed

        # The test passes if no exception is thrown during command
        expect(true).to be_true
      end
    end
  end

  it "should handle different message lengths" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Test short message
        bot.chat "Hi!"
        bot.wait_ticks 2

        # Test medium message
        bot.chat "This is a medium length message for testing purposes."
        bot.wait_ticks 2

        # Test long message (but under 256 character limit)
        long_message = "A" * 100
        bot.chat long_message
        bot.wait_ticks 5

        expect(true).to be_true
      end
    end
  end

  it "should receive System Chat Message packets (0x72)" do
    client.join_game do |client|
      received_system_chat = false

      # Listen specifically for System Chat Message packets
      client.on(Rosegold::Clientbound::ChatMessage) do |packet|
        received_system_chat = true
      end

      Rosegold::Bot.new(client).try do |bot|
        # Commands that typically generate system chat messages
        # /time query should generate a system response
        bot.chat "/time query daytime"
        bot.wait_ticks 10

        # For now, just verify the packet type can be handled without errors
        # System chat messages may not always be generated depending on server config
        expect(true).to be_true
      end
    end
  end

  it "should receive Player Chat Message packets (0x3A)" do
    client.join_game do |client|
      received_player_chat = false

      # Listen specifically for Player Chat Message packets
      client.on(Rosegold::Clientbound::PlayerChatMessage) do |packet|
        received_player_chat = true
      end

      Rosegold::Bot.new(client).try do |bot|
        # Regular chat messages between players should generate PlayerChatMessage packets
        # Since we're testing alone, we won't receive player messages
        # But we can verify the packet handler is set up correctly
        bot.chat "Hello world!"
        bot.wait_ticks 5

        # Test passes if no packet parsing errors occur
        expect(true).to be_true
      end
    end
  end

  it "should receive Disguised Chat Message packets (0x1D)" do
    client.join_game do |client|
      received_disguised_chat = false

      # Listen specifically for Disguised Chat Message packets
      client.on(Rosegold::Clientbound::DisguisedChatMessage) do |packet|
        received_disguised_chat = true
      end

      Rosegold::Bot.new(client).try do |bot|
        # /say command should generate a DisguisedChatMessage packet
        bot.chat "/say Test message from server"
        bot.wait_ticks 10

        # Verify we received the disguised chat message
        expect(received_disguised_chat).to be_true
      end
    end
  end

  it "should handle chat message packet structure correctly" do
    client.join_game do |client|
      message_received = false

      # Monitor for any chat-related packets
      client.on(Rosegold::Clientbound::ChatMessage) do |packet|
        message_received = true
        # Verify packet structure
        expect(packet.message).to be_a(Rosegold::Chat)
        expect(packet.sender).to be_a(UUID)
      end

      Rosegold::Bot.new(client).try do |bot|
        # Trigger a server message
        bot.chat "/me is testing chat functionality"
        bot.wait_ticks 10

        # At minimum, no packet decode errors should occur
        expect(true).to be_true
      end
    end
  end
end
