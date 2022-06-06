require "./microsoft/mobile_oauth"

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
      "RpsTicket"  => "d=#{Microsoft::MobileOAuth.prompt_for_login!}",
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
            puts "ACCESS_TOKEN=#{json["access_token"]}"

            HTTP::Client.get("https://api.minecraftservices.com/minecraft/profile",
              headers: HTTP::Headers{
                "Content-Type"  => "application/json",
                "Accept"        => "application/json",
                "Authorization" => "Bearer #{json["access_token"]}",
              }
            ) do |response|
              JSON.parse(response.body_io.gets_to_end).try do |json|
                puts "UUID=#{json["id"]}"
                puts "MC_NAME=#{json["name"]}"
              end
            end
          end
        end
      end
    end
  end
end
