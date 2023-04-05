require "./minecraft/auth"
minecraft_auth = Minecraft::Auth.new
authentication = minecraft_auth.authenticate

puts "Authenticated as #{authentication["mc_name"]}"
ENV["ACCESS_TOKEN"] = authentication["access_token"]
ENV["UUID"] = authentication["uuid"]
ENV["MC_NAME"] = authentication["mc_name"]

require "./rosegold"
require "./rosegold/bot"

include Rosegold

def show_help
  puts "Rosegold v#{Rosegold::VERSION}"
  puts "~"*20
  puts "\\help - This help screen"
  puts "\\position - Displays the current coordinates of the player"
end

Client.new(ENV["HOST"]).join_game do |client|
  bot = Rosegold::Bot.new client

  show_help

  spawn do
    loop do
      bot.move_to rand(-10..10), rand(-10..10)
      sleep 3
    end
  end

  while input = gets
    next if input.empty?

    bot.chat input unless input.starts_with? "\\"

    command = input.split(" ")
    case command.first
    when "\\help"
      show_help
    when "\\position"
      puts bot.feet
    when "\\pitch"
      if command.size > 1
        bot.look &.with_pitch command[1].to_f.to_f32
      else
        puts bot.look.pitch
      end
    when "\\yaw"
      if command.size > 1
        bot.look &.with_yaw command[1].to_f.to_f32
      else
        puts bot.look.yaw
      end
    when "\\move"
      spawn do
        location = Vec3d.new command[1].to_f, bot.feet.y, command[3].to_f
        begin
          bot.move_to location
          puts "Arrived at #{bot.feet}"
        rescue ex
          puts "Movement to #{location} failed:"
          puts ex
        end
      end
    when "\\jump"
      bot.start_jump
    when "\\debug"
      Log.setup :debug
    when "\\trace"
      Log.setup :trace
    end
  end
end
