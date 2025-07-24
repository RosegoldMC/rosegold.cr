require "../spec_helper"

Spectator.describe "Rosegold::Bot event emitter" do
  it "should emit chat events" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        test = false
        bot.on Rosegold::Clientbound::DisguisedChatMessage do |event|
          test = true
        end
        bot.chat "/say Hello from bot event emitter test!"
        client.wait_for Rosegold::Clientbound::DisguisedChatMessage
        expect(test).to be true
      end
    end
  end

  it "should return the id, usable with #off" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        test = false
        uuid = bot.on Rosegold::Clientbound::DisguisedChatMessage do |event|
          test = true
        end
        bot.chat "/say Hello from bot event emitter test!"
        client.wait_for Rosegold::Clientbound::DisguisedChatMessage
        expect(test).to be true
        expect(uuid).to be_a UUID
        expect { bot.off Rosegold::Clientbound::DisguisedChatMessage, uuid }.not_to raise_error
      end
    end
  end

  describe "#once" do
    it "should only emit once" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          test = 0
          bot.once Rosegold::Clientbound::DisguisedChatMessage do |_event|
            test += 1
          end
          bot.chat "/say First message"
          client.wait_for Rosegold::Clientbound::DisguisedChatMessage
          bot.chat "/say Second message"
          client.wait_for Rosegold::Clientbound::DisguisedChatMessage
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
            ran_event = bot.wait_for Rosegold::Clientbound::DisguisedChatMessage
          end

          expect(ran_event).to be nil
          bot.chat "/say Hello from wait_for test!"
          ticks = 0
          until ran_event || ticks > 100
            bot.wait_tick
            ticks += 1
          end
          expect(ran_event).to be_a Rosegold::Clientbound::DisguisedChatMessage
        end
      end
    end

    context "when a timeout is specified" do
      it "works like normal when the event is received" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            ran_event = nil
            spawn do
              ran_event = bot.wait_for Rosegold::Clientbound::DisguisedChatMessage, timeout: Time::Span.new(seconds: 1)
            end

            expect(ran_event).to be nil
            bot.chat "/say Hello from timeout test!"
            # until ran event or 5 seconds
            ticks = 0
            until ran_event || ticks > 100
              bot.wait_tick
              ticks += 1
            end
            expect(ran_event).to be_a Rosegold::Clientbound::DisguisedChatMessage
          end
        end
      end

      it "returns nil when the event is not received in time" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            ran_event = nil
            spawn do
              ran_event = bot.wait_for Rosegold::Clientbound::DisguisedChatMessage, timeout: Time::Span.new(nanoseconds: 1)
            end

            expect(ran_event).to be nil
            bot.wait_tick # enough to go beyond the 1 nanosecond timeout
            bot.chat "/say This should timeout!"
            bot.wait_tick
            expect(ran_event).to be nil
          end
        end
      end
    end
  end
end
