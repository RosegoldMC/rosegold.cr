require "../spec_helper"

Spectator.describe "Rosegold::Bot attack" do
  after_each do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_tick
      end
    end
  end

  it "should be able to attack even if the target is moving" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp @p -9 -60 9"
        bot.chat "/time set 13000"
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/clear"
        bot.wait_for Rosegold::Clientbound::SetSlot

        bot.chat "/give #{bot.username} minecraft:diamond_sword"
        bot.wait_for Rosegold::Clientbound::SetSlot
        bot.chat "/fill -10 -60 8 0 -58 6 minecraft:dirt"
        bot.chat "/fill -9 -60 7 0 -58 7 minecraft:air"
        bot.wait_tick
        bot.chat "/fill -6 -60 7 -6 -60 7 minecraft:water"
        bot.wait_tick
        bot.chat "/fill -9 -59 8 -9 -59 8 minecraft:air"
        bot.wait_tick
        bot.chat "/summon minecraft:zombie -7 -60 7"

        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0
        20.times do
          break if client.dimension.entities.select { |_, e| e.entity_type == 107 }.empty?
          bot.chat "attack!"
          bot.attack
          bot.wait_ticks 13
        end
        # no zombies left
        expect(client.dimension.entities.select { |_, e| e.entity_type == 107 }).to be_empty
      end
    end
  end

  it "should not be able to attack entities through blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Position player at a specific location
        bot.chat "/tp @p 0 -60 0"
        bot.chat "/time set 13000"
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/clear"
        bot.wait_for Rosegold::Clientbound::SetSlot

        bot.chat "/give #{bot.username} minecraft:diamond_sword"
        bot.wait_for Rosegold::Clientbound::SetSlot

        # Clear the area first
        bot.chat "/fill -2 -61 -2 2 -58 2 minecraft:air"
        bot.wait_tick

        # Place bedrock floor
        bot.chat "/fill -2 -61 -2 2 -61 2 minecraft:bedrock"
        bot.wait_tick

        # Place a stone block between player and where zombie will be
        bot.chat "/setblock 0 -60 1 minecraft:stone"
        bot.wait_tick

        # Summon zombie behind the block (should be blocked by stone)
        bot.chat "/summon minecraft:zombie 0 -60 2"
        bot.wait_tick

        bot.inventory.pick! "diamond_sword"

        # Aim towards the zombie (north, towards positive Z)
        bot.yaw = 0.0   # North
        bot.pitch = 0.0 # Level

        # Wait a moment for everything to settle
        bot.wait_ticks 10

        # Count zombies before attack
        zombies_before = client.dimension.entities.count { |_, e| e.entity_type == 107 }

        # Try to attack multiple times - should not hit the zombie through the block
        5.times do
          bot.attack
          bot.wait_ticks 5
        end

        # Wait a bit more to ensure any delayed effects are processed
        bot.wait_ticks 10

        # Count zombies after attack - should be the same (zombie should still be alive)
        zombies_after = client.dimension.entities.count { |_, e| e.entity_type == 107 }

        # The zombie should still be alive because the block prevented the attack
        expect(zombies_after).to eq(zombies_before)
        expect(zombies_after).to eq(1)
      end
    end
  end
end
