require "./minecraft/auth"

minecraft_auth = Minecraft::Auth.new
authentication = minecraft_auth.authenticate

puts "ACCESS_TOKEN=#{authentication["access_token"]}"
puts "UUID=#{authentication["uuid"]}"
puts "MC_NAME=#{authentication["mc_name"]}"
