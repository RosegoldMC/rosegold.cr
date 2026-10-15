require "../src/rosegold"

SERVER = ENV.fetch("ROSEGOLD_SERVER", "localhost:25565")

Rosegold::Bot.run(SERVER) do |bot|
  bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
    puts "#{event.network_name}: #{event.message}"
  end

  while bot.connected?
    bot.wait_tick
  end
end
