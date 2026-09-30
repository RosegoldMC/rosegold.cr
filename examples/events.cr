require "../src/rosegold"

SERVER = ENV.fetch("ROSEGOLD_SERVER", "localhost:25565")

bot = Rosegold::Bot.new(SERVER)
eating = false

bot.on Rosegold::Clientbound::PlayerChatMessage do |event|
  puts "#{event.network_name}: #{event.message}"
end

bot.on Rosegold::Event::HealthChanged do |event|
  puts "health=#{event.health}, food=#{event.food}"
  next if event.food >= 12 || eating

  eating = true
  spawn do
    begin
      bot.eat!
    rescue ex
      Log.warn { "Eating failed: #{ex.message}" }
    ensure
      eating = false
    end
  end
end

begin
  bot.join_game
  bot.chat "Listening for chat."
  bot.wait_ticks(1200)
ensure
  bot.disconnect("Event example finished") if bot.connected?
end
