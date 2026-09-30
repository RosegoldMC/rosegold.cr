require "../src/rosegold"

SERVER = ENV.fetch("ROSEGOLD_SERVER", "localhost:25565")

bot = Rosegold::Bot.new(SERVER)

begin
  bot.join_game
  bot.chat "Patrol starting."

  origin = bot.location
  [
    origin,
    origin.plus(8.0, 0.0, 0.0),
    origin.plus(8.0, 0.0, 8.0),
    origin.plus(0.0, 0.0, 8.0),
  ].each do |destination|
    bot.move_to(destination)
    bot.eat! if bot.should_eat?
    bot.wait_ticks(10)
  end

  bot.chat "Patrol complete."
ensure
  bot.disconnect("Patrol finished") if bot.connected?
end
