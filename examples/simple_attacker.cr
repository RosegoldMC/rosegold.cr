require "../src/rosegold"

include Rosegold

# A simple bot that attacks at a specific location
# and then waits 20 ticks before attacking again

bot = Rosegold::Bot.join_game("play.civmc.net")
sleep 3

while bot.connected?
  bot.eat!
  bot.yaw = -90
  bot.pitch = -10
  bot.inventory.pick! "diamond_sword"
  bot.attack
  bot.wait_ticks 20
  puts bot.feet
  puts "Tool durability: #{bot.main_hand.durability} / #{bot.main_hand.max_durability}"
end
