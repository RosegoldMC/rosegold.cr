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

  it "should return the id, usable with #off" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        test = false
        uuid = bot.on Rosegold::Clientbound::ChatMessage do |event|
          if event.message.to_s == "<#{client.player.username}> Hello, world!"
            test = true
          end
        end
        bot.chat "Hello, world!"
        bot.wait_tick
        expect(test).to be true
        expect(uuid).to be_a UUID
        expect { bot.off Rosegold::Clientbound::ChatMessage, uuid }.not_to raise_error
      end
    end
  end

  describe "#once" do
    it "should only emit once" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          test = 0
          bot.once Rosegold::Clientbound::ChatMessage do |_event|
            test += 1
          end
          bot.chat "Hello, world!"
          bot.wait_tick
          bot.chat "Hello, world!"
          bot.wait_tick
          expect(test).to eq 1
        end
      end
    end
  end

  describe "#wait_for" do
    it "should wait for an event" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          ran_event = nil
          spawn do
            ran_event = bot.wait_for Rosegold::Clientbound::ChatMessage
          end

          expect(ran_event).to be nil
          bot.chat "Hello, world!"
          bot.wait_tick
          expect(ran_event).to be_a Rosegold::Clientbound::ChatMessage
        end
      end
    end

    context "when a timeout is specified" do
      it "works like normal when the event is received" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            ran_event = nil
            spawn do
              ran_event = bot.wait_for Rosegold::Clientbound::ChatMessage, timeout: Time::Span.new(seconds: 1)
            end

            expect(ran_event).to be nil
            bot.chat "Hello, world!"
            bot.wait_tick
            expect(ran_event).to be_a Rosegold::Clientbound::ChatMessage
          end
        end
      end

      it "returns nil when the event is not received in time" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            ran_event = nil
            spawn do
              ran_event = bot.wait_for Rosegold::Clientbound::ChatMessage, timeout: Time::Span.new(nanoseconds: 1)
            end

            expect(ran_event).to be nil
            bot.wait_tick # enough to go beyond the 1 nanosecond timeout
            bot.chat "Hello, world!"
            bot.wait_tick
            expect(ran_event).to be nil
          end
        end
      end
    end
  end
end
