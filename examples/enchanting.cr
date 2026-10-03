require "../src/rosegold"

unless ARGV.size == 2
  abort "Usage: crystal run examples/enchanting.cr -- YAW PITCH"
end

yaw = ARGV[0].to_f32
pitch = ARGV[1].to_f32
bot = Rosegold::Bot.new(ENV.fetch("ROSEGOLD_SERVER", "localhost:25565"))

begin
  bot.join_game
  bot.look = Rosegold::Look.new(yaw, pitch)
  enchanted = bot.enchant("diamond_pickaxe", option: 2)
  puts "enchanted pickaxe: #{enchanted.enchantments}"
ensure
  bot.disconnect("Enchanting example finished") if bot.connected?
end
