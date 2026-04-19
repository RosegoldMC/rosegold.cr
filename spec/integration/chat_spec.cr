require "../spec_helper"

Spectator.describe "Rosegold::Bot chat functionality" do
  it "should send chat messages and commands without error" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "Hi!"
        bot.chat "This is a medium length message for testing purposes."
        bot.chat "A" * 100
        bot.chat "/time query daytime"
        bot.wait_ticks 2

        expect(client.connected?).to be_true
      end
    end
  end

  it "should receive Disguised Chat Message packets" do
    client.join_game do |client|
      received_disguised_chat = false

      client.on(Rosegold::Clientbound::DisguisedChatMessage) do |_|
        received_disguised_chat = true
      end

      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/say Test message from server"
        bot.wait_ticks 10
      end

      expect(received_disguised_chat).to be_true
    end
  end

  it "should receive System Chat Message packets with correct structure" do
    client.join_game do |client|
      received_packet : Rosegold::Clientbound::SystemChatMessage? = nil

      client.on(Rosegold::Clientbound::SystemChatMessage) do |packet|
        received_packet ||= packet
      end

      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/time query daytime"
        bot.wait_ticks 10
      end

      expect(received_packet).to_not be_nil
      expect(received_packet.try(&.message)).to be_a(Rosegold::TextComponent)
      expect(received_packet.try(&.overlay?)).to be_a(Bool)
    end
  end
end
