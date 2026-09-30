require "../src/rosegold"

unless ARGV.size == 3
  abort "Usage: crystal run examples/container.cr -- X Y Z"
end

target = Rosegold::Vec3i.new(ARGV[0].to_i, ARGV[1].to_i, ARGV[2].to_i)
bot = Rosegold::Bot.new(ENV.fetch("ROSEGOLD_SERVER", "localhost:25565"))

begin
  bot.join_game
  bot.look_at(target + BlockFace::Top)
  bot.open_container_handle do |container|
    puts "cobblestone in container: #{container.count_in_container("cobblestone")}"
    puts "cobblestone in inventory: #{container.count_in_player("cobblestone")}"
  end
ensure
  bot.disconnect("Container inspection finished") if bot.connected?
end
