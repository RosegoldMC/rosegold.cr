require "./rosegold"
require "./microsoft/mobile_oauth"

def show_help
  puts "Rosegold v#{Rosegold::VERSION}"
  puts "~"*20
  puts "\\help - This help screen"
  puts "\\position - Displays the current coordinates of the player"
end

def startClient
  Rosegold::Client.new("icenia-creative.mcnetwork.me", 25565).start do |bot|
    show_help

    spawn do
      loop do
        bot.move_to rand(-10..10), -60, rand(-10..10)
        sleep 3
      end
    end

    loop do
      gets.try do |input|
        next if input.empty?

        if input.starts_with? "\\"
          command = input.split(" ")
          case command.first
          when "\\help"
            show_help
          when "\\position"
            puts bot.player.feet
          when "\\pitch"
            if command.size > 1
              bot.pitch = command[1].to_f
            else
              puts bot.pitch
            end
          when "\\yaw"
            if command.size > 1
              bot.yaw = command[1].to_f
            else
              puts bot.yaw
            end
          when "\\move"
            bot.move_to command[1].to_f, command[2].to_f, command[3].to_f
          when "\\jump"
            bot.jump
          when "\\debug"
            Log.setup :debug
          when "\\trace"
            Log.setup :trace
          end

          next
        end

        bot.chat input
      end
    end
  end
end

ticket = Microsoft::MobileOAuth.prompt_for_login!

HTTP::Client.post(
  "https://user.auth.xboxlive.com/user/authenticate",
  headers: HTTP::Headers{
    "Content-Type" => "application/json",
    "Accept"       => "application/json",
  },
  body: {
    "Properties" => {
      "AuthMethod" => "RPS",
      "SiteName"   => "user.auth.xboxlive.com",
      "RpsTicket"  => "d=#{ticket}",
    },
    "RelyingParty" => "http://auth.xboxlive.com",
    "TokenType"    => "JWT",
  }.to_json,
) do |response|
  JSON.parse(response.body_io.gets_to_end).try do |json|
    token = json["Token"]
    uhs = json["DisplayClaims"]["xui"].as_a.first["uhs"]
    HTTP::Client.post("https://xsts.auth.xboxlive.com/xsts/authorize",
      headers: HTTP::Headers{
        "Content-Type" => "application/json",
        "Accept"       => "application/json",
      },
      body: {
        "Properties" => {
          "SandboxId"  => "RETAIL",
          "UserTokens" => [
            token,
          ],
        },
        "RelyingParty" => "rp://api.minecraftservices.com/",
        "TokenType"    => "JWT",
      }.to_json
    ) do |response|
      JSON.parse(response.body_io.gets_to_end).try do |json|
        token = json["Token"]

        HTTP::Client.post("https://api.minecraftservices.com/authentication/login_with_xbox",
          headers: HTTP::Headers{
            "Content-Type" => "application/json",
            "Accept"       => "application/json",
          },
          body: {
            "identityToken" => "XBL3.0 x=#{uhs};#{token}",
          }.to_json
        ) do |response|
          JSON.parse(response.body_io.gets_to_end).try do |json|
            ENV["ACCESS_TOKEN"] = json["access_token"].as_s

            HTTP::Client.get("https://api.minecraftservices.com/minecraft/profile",
              headers: HTTP::Headers{
                "Content-Type"  => "application/json",
                "Accept"        => "application/json",
                "Authorization" => "Bearer #{json["access_token"]}",
              }
            ) do |response|
              JSON.parse(response.body_io.gets_to_end).try do |json|
                ENV["UUID"] = json["id"].as_s
                ENV["MC_NAME"] = json["name"].as_s
                
                startClient

              end
            end
          end
        end
      end
    end
  end
end
