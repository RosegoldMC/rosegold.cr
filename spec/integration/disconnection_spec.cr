require "../spec_helper"
require "log/spec"

Spectator.describe "Rosegold::Client disconnection" do
  it "should handle disconnection via kick command" do
    client.join_game do |client|
      disconnected = false
      disconnect_reason : Rosegold::TextComponent? = nil

      client.on(Rosegold::Event::Disconnected) do |event|
        disconnected = true
        disconnect_reason = event.reason
      end

      Rosegold::Bot.new(client).try do |bot|
        username = client.player.username
        bot.chat "/kick #{username}"
        bot.wait_ticks 10

        expect(disconnected).to be_true
        expect(disconnect_reason).to_not be_nil
      end
    end
  end

  it "should log disconnect reason clearly without IO error" do
    Log.capture("rosegold") do |logs|
      begin
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            username = client.player.username
            bot.chat "/kick #{username}"
            bot.wait_ticks 10
          end
        end
      rescue Rosegold::Client::NotConnected
      end

      logs.check(:info, /Disconnected:.*Kicked/i)
    end
  end
end
