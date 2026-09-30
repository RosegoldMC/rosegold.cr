require "../src/rosegold"

SERVER = ENV.fetch("ROSEGOLD_SERVER", "localhost")
PORT   = ENV.fetch("ROSEGOLD_PORT", "25565").to_i

client = Rosegold::Client.new(SERVER, PORT)
bot = Rosegold::Bot.new(client)
spectate = Rosegold::SpectateServer.new

spectate.attach_client(client)
spectate.start

begin
  bot.join_game
  spectate.chat "Bot connected"
  spectate.action_bar "Walking a small square"
  spectate.boss_bar "Distance", 0, 1

  origin = bot.location
  [
    origin.plus(4.0, 0.0, 0.0),
    origin.plus(4.0, 0.0, 4.0),
    origin.plus(0.0, 0.0, 4.0),
    origin,
  ].each do |destination|
    bot.move_to(destination)
  end
ensure
  spectate.stop
  bot.disconnect("Spectate example finished") if bot.connected?
end
