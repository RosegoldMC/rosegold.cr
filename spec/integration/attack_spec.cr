require "../spec_helper"

Spectator.describe "Rosegold::Bot attack" do
  before_each do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_ticks 5
        bot.chat "/tp @p -9 -60 9"
        bot.chat "/time set 13000"
        bot.chat "/clear"
        bot.wait_for Rosegold::Clientbound::SetSlot

        bot.chat "/give #{bot.username} minecraft:diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        bot.chat "/effect give #{bot.username} minecraft:strength 60 2"
        bot.wait_for Rosegold::Clientbound::SetSlot
        bot.chat "/fill -10 -60 8 0 -58 6 minecraft:obsidian"
        bot.chat "/fill -9 -60 7 0 -58 7 minecraft:air"
        bot.wait_tick
        bot.chat "/fill -6 -60 7 -6 -60 7 minecraft:water"
        bot.wait_tick
      end
    end
  end

  after_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
      end
    end

  it "should be able to attack even if the target is moving" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill -9 -59 8 -9 -59 8 minecraft:air"
        bot.wait_tick
        bot.chat "/summon minecraft:zombie -7 -60 7"

        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0

        20.times do
          break if client.dimension.entities.select { |_, e| e.entity_type == 145 }.empty?
          bot.attack
          bot.wait_ticks 13
        end
        # no zombies left
        expect(client.dimension.entities.select { |_, e| e.entity_type == 145 }).to be_empty
      end
    end
  end

  it "should not be able to attack entities through blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/summon minecraft:zombie -7 -60 7"
        bot.inventory.pick! "diamond_sword"

        # Aim towards the zombie (south, towards negative Z)
        bot.yaw = 180.0 # South (towards the zombie at Z=7 from bot at Z=9)
        bot.pitch = 0.0 # Level

        # Wait a moment for everything to settle
        bot.wait_ticks 10

        # Additional verification: count zombies before attack
        zombies_before = client.dimension.entities.count { |_, e| e.entity_type == 145 }
        expect(zombies_before).to eq(1) # Ensure zombie is present

        # Try to attack multiple times - should not hit the zombie through the block
        10.times do # Increased from 5 to ensure zombie would definitely die if hit
          bot.attack
          bot.wait_ticks 5
        end

        # Wait a bit more to ensure any delayed effects are processed
        bot.wait_ticks 10

        # Count zombies after attack - should be the same (zombie should still be alive)
        zombies_after = client.dimension.entities.count { |_, e| e.entity_type == 145 }

        # The zombie should still be alive because the block prevented the attack
        expect(zombies_after).to eq(zombies_before)
        expect(zombies_after).to eq(1)
      end
    end
  end
end
