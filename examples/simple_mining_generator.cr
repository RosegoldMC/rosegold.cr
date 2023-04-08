require "../src/rosegold"

include Rosegold

# A simple bot that just mines a block in front of it
# Good for cobble/obby generators
# Adjust bot.yaw = 90 to change direction

bot = Rosegold::Bot.join_game("play.civmc.net")
sleep 3

while bot.connected?
  bot.pitch = 0
  bot.yaw = -90

  bot.inventory.pick! "diamond_pickaxe"
  bot.start_digging
  sleep 1
  puts "Current Tool's Damage: #{bot.main_hand.damage}"
end
