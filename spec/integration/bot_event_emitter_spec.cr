require "../spec_helper"

Spectator.describe "Rosegold::Bot event emitter" do
  it "should emit chat events" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        test = false
        bot.on Rosegold::Clientbound::ChatMessage do |event|
          if event.message.to_s == "<#{client.player.username}> Hello, world!"
            test = true
          end
        end
        bot.chat "Hello, world!"
        bot.wait_tick
        expect(test).to be true
      end
    end
  end
end
