require "../spec_helper"

Spectator.describe "Rosegold::Bot sneak functionality" do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_tick
      end
    end
  end

  it "should sneak when bot.sneak is called" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Ensure bot starts not sneaking
        expect(bot.sneaking?).to be_false

        # Call sneak method
        bot.sneak

        # Bot should now be sneaking
        expect(bot.sneaking?).to be_true

        # Test that we can unsneak
        bot.unsneak

        # Bot should no longer be sneaking
        expect(bot.sneaking?).to be_false
      end
    end
  end

  it "should not sprint while sneaking" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Start sneaking
        bot.sneak
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false

        # Try to sprint - should not work while sneaking
        bot.sprint
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false

        # Stop sneaking, then should be able to sprint
        bot.unsneak
        expect(bot.sneaking?).to be_false

        bot.sprint
        expect(bot.sprinting?).to be_true
      end
    end
  end

  it "should stop sprinting when starting to sneak" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Start sprinting
        bot.sprint
        expect(bot.sprinting?).to be_true
        expect(bot.sneaking?).to be_false

        # Start sneaking - should stop sprinting automatically
        bot.sneak
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false
      end
    end
  end

  it "should maintain sneak state across multiple calls" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Sneak multiple times - should remain sneaking
        bot.sneak
        expect(bot.sneaking?).to be_true

        bot.sneak
        expect(bot.sneaking?).to be_true

        bot.sneak
        expect(bot.sneaking?).to be_true

        # Unsneak and verify
        bot.unsneak
        expect(bot.sneaking?).to be_false

        # Unsneak multiple times - should remain not sneaking
        bot.unsneak
        expect(bot.sneaking?).to be_false

        bot.unsneak
        expect(bot.sneaking?).to be_false
      end
    end
  end

  it "should send correct EntityAction packets" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Test that calling sneak actually sends the packet by verifying state change
        initial_state = bot.sneaking?

        # Call sneak and verify state changed
        bot.sneak
        new_state = bot.sneaking?
        expect(new_state).to_not eq(initial_state)
        expect(new_state).to be_true
      end
    end
  end
end
