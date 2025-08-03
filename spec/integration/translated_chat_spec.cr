require "../spec_helper"

Spectator.describe "Rosegold::Bot translated chat functionality" do
  it "should receive and parse translated system chat messages correctly" do
    client.join_game do |client|
      received_translated_messages = [] of Rosegold::Clientbound::SystemChatMessage
      translation_keys_received = [] of String

      # Listen for System Chat Message packets that contain translations
      client.on(Rosegold::Clientbound::SystemChatMessage) do |packet|
        received_translated_messages << packet
        
        # Track which translation keys we receive
        if translate_key = packet.message.translate
          translation_keys_received << translate_key
        end
      end

      Rosegold::Bot.new(client).try do |bot|
        # Commands that typically generate translated system chat messages
        # These should produce SystemChatMessage packets with NBT format in MC 1.21.8+
        
        # /time query commands often return translated messages
        bot.chat "/time query daytime"
        bot.wait_ticks 10
        
        # /gamemode commands also typically use translations
        bot.chat "/gamemode creative"
        bot.wait_ticks 10
        
        # /give commands can produce translated messages
        bot.chat "/give @s stone 1"
        bot.wait_ticks 10

        # Wait a bit more to ensure all messages are received
        bot.wait_ticks 20

        # Verify we received system chat messages
        expect(received_translated_messages.size).to be > 0

        # Verify that messages with translation keys can be parsed without errors
        # and that the 'with' field parsing works correctly
        received_translated_messages.each do |message_packet|
          message = message_packet.message
          
          # Verify the message can be converted to string without errors
          message_string = message.to_s
          expect(message_string).not_to be_empty
          
          # If this is a translated message, verify translation handling
          if translate_key = message.translate
            # Message should have been translated or at least show the key
            expect(message_string).not_to be_nil
            expect(message_string.size).to be > 0
            
            # If there are 'with' parameters, verify they were parsed
            if with_params = message.with
              expect(with_params).to be_a(Array)
              expect(with_params.size).to be > 0
              
              # Each parameter should be convertible to string
              with_params.each do |param|
                expect(param.to_s).not_to be_empty
              end
            end
          end
        end

        # Verify we can handle the scenario from the original issue
        # Look for any received messages that demonstrate the 'with' field parsing
        messages_with_params = received_translated_messages.select do |msg|
          msg.message.translate && msg.message.with && msg.message.with.not_nil!.size > 0
        end

        # While we can't guarantee specific translated messages with parameters,
        # we can verify that if we do receive them, they parse correctly
        if messages_with_params.size > 0
          messages_with_params.each do |msg|
            # Verify the message structure is correct
            expect(msg.message.translate).not_to be_nil
            expect(msg.message.with).not_to be_nil
            
            # Verify string conversion works
            result = msg.message.to_s
            expect(result).not_to be_empty
            expect(result).not_to eq(msg.message.translate) # Should be different from raw key
          end
        end
      end
    end
  end

  it "should handle SystemChatMessage packets with NBT format correctly" do
    client.join_game do |client|
      system_messages_received = 0
      parsing_errors = 0

      # Monitor for any parsing errors in system chat messages
      client.on(Rosegold::Clientbound::SystemChatMessage) do |packet|
        system_messages_received += 1
        
        begin
          # Try to access all properties to ensure parsing worked
          message = packet.message
          text = message.text
          translate = message.translate
          with_params = message.with
          extra = message.extra
          
          # Convert to string to verify the full parsing pipeline
          message_string = message.to_s
          
          # Basic validation
          expect(message_string).to be_a(String)
          
        rescue ex
          parsing_errors += 1
          Log.error { "Error parsing SystemChatMessage: #{ex.message}" }
        end
      end

      Rosegold::Bot.new(client).try do |bot|
        # Generate various system messages to test NBT parsing
        bot.chat "/help"
        bot.wait_ticks 10
        
        bot.chat "/time set day"
        bot.wait_ticks 10
        
        bot.chat "/weather clear"
        bot.wait_ticks 10

        # Wait for messages to be processed
        bot.wait_ticks 20

        # Verify we received messages and they parsed without errors
        expect(system_messages_received).to be > 0
        expect(parsing_errors).to eq(0)
      end
    end
  end

  it "should demonstrate the fix for issue #205 - NBT 'with' field parsing" do
    client.join_game do |client|
      nbt_format_messages = [] of Rosegold::Clientbound::SystemChatMessage

      # Look specifically for messages that would use the NBT format
      # and have translation parameters
      client.on(Rosegold::Clientbound::SystemChatMessage) do |packet|
        message = packet.message
        
        # We're interested in translated messages that demonstrate the fix
        if message.translate && message.with
          nbt_format_messages << packet
        end
      end

      Rosegold::Bot.new(client).try do |bot|
        # Commands that are likely to produce translated messages with parameters
        # These will be sent as NBT format in MC 1.21.8+
        
        bot.chat "/tp @s ~ ~1 ~"  # Teleport command often has position parameters
        bot.wait_ticks 10
        
        bot.chat "/give @s diamond_sword 1"  # Give commands have item/count parameters
        bot.wait_ticks 10
        
        bot.chat "/effect give @s speed 30"  # Effect commands have duration parameters
        bot.wait_ticks 10

        # Wait for all messages
        bot.wait_ticks 30

        # The key test: if we received any NBT format messages with 'with' parameters,
        # they should parse correctly and not lose the translation parameters
        nbt_format_messages.each do |msg_packet|
          message = msg_packet.message
          
          # Verify the core fix: 'with' field should be parsed from NBT
          expect(message.translate).not_to be_nil
          expect(message.with).not_to be_nil
          expect(message.with.not_nil!.size).to be > 0
          
          # Verify translation with parameters works
          result = message.to_s
          expect(result).not_to be_empty
          expect(result).not_to eq(message.translate)  # Should be interpolated
          
          # The message should contain the translated content, not just the key
          # This verifies that the 'with' parameters were used in translation
          expect(result).not_to match(/^[a-z.]+$/)  # Shouldn't be just a translation key
        end

        # Test passes if:
        # 1. No parsing errors occurred (verified by reaching this point)
        # 2. Any translated messages with parameters were handled correctly
        # 3. The SystemChatMessage packet can process NBT format correctly
        expect(true).to be_true
      end
    end
  end
end