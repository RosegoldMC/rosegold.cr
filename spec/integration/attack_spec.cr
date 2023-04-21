require "../spec_helper"

Spectator.describe Rosegold::Bot do
  after_each do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        sleep 1
      end
    end
  end

  it "should be able to attack" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp @p -9 -60 9"
        bot.chat "/time set 13000"
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/clear"
        sleep 1
        bot.chat "/give #{bot.username} minecraft:diamond_sword"
        bot.chat "/summon minecraft:zombie -9 -60 8 {NoAI:1}"
        sleep 1
        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0
        20.times do
          break if client.dimension.entities.select { |_, e| e.entity_type == 107 }.empty?
          bot.chat "attack!"
          bot.attack
          bot.wait_ticks 20
        end
        # no zombies left
        expect(client.dimension.entities.select { |_, e| e.entity_type == 107 }).to be_empty
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
        bot.wait_ticks 5
        bot.chat "/give #{bot.username} minecraft:diamond_sword"
        bot.wait_tick
        bot.chat "/fill -10 -60 8 0 -58 6 minecraft:dirt"
        bot.wait_tick
        bot.chat "/fill -9 -60 7 0 -58 7 minecraft:air"
        bot.wait_tick
        bot.chat "/fill -6 -60 7 -6 -60 7 minecraft:water"
        bot.wait_tick
        bot.chat "/fill -9 -59 8 -9 -59 8 minecraft:air"
        bot.wait_tick
        bot.chat "/summon minecraft:zombie -7 -60 7"
        sleep 1
        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0
        20.times do
          break if client.dimension.entities.select { |_, e| e.entity_type == 107 }.empty?
          bot.chat "attack!"
          bot.attack
          bot.wait_ticks 20
        end
        # no zombies left
        expect(client.dimension.entities.select { |_, e| e.entity_type == 107 }).to be_empty
      end
    end
  end
end
