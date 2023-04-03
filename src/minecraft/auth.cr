require "http"
require "json"
require "../microsoft/mobile_oauth"

class Minecraft::Auth
  @xbox_token : String?
  @uhs : String?
  @xsts_token : String?
  @access_token : String?
  @uuid : String?
  @mc_name : String?

  def initialize
    @ticket = Microsoft::MobileOAuth.prompt_for_login!
  end

  def authenticate
    xbox_authenticate
    xsts_authorize
    login_with_xbox
    get_minecraft_profile
  end

  private def xbox_authenticate
    response = HTTP::Client.post("https://user.auth.xboxlive.com/user/authenticate",
      headers: headers,
      body: {
        "Properties" => {
          "AuthMethod" => "RPS",
          "SiteName"   => "user.auth.xboxlive.com",
          "RpsTicket"  => "d=#{@ticket}",
        },
        "RelyingParty" => "http://auth.xboxlive.com",
        "TokenType"    => "JWT",
      }.to_json)

    json = JSON.parse(response.body)
    @xbox_token = json["Token"].as_s
    @uhs = json["DisplayClaims"]["xui"].as_a.first["uhs"].as_s
  end

  private def xsts_authorize
    response = HTTP::Client.post("https://xsts.auth.xboxlive.com/xsts/authorize",
      headers: headers,
      body: {
        "Properties" => {
          "SandboxId"  => "RETAIL",
          "UserTokens" => [
            @xbox_token,
          ],
        },
        "RelyingParty" => "rp://api.minecraftservices.com/",
        "TokenType"    => "JWT",
      }.to_json)

    json = JSON.parse(response.body)
    @xsts_token = json["Token"].as_s
  end

  private def login_with_xbox
    response = HTTP::Client.post("https://api.minecraftservices.com/authentication/login_with_xbox",
      headers: headers,
      body: {
        "identityToken" => "XBL3.0 x=#{@uhs};#{@xsts_token}",
      }.to_json)

    json = JSON.parse(response.body)
    @access_token = json["access_token"].as_s
  end

  private def get_minecraft_profile
    response = HTTP::Client.get("https://api.minecraftservices.com/minecraft/profile",
      headers: headers.merge!({"Authorization" => "Bearer #{@access_token}"}))

    json = JSON.parse(response.body)
    @uuid = json["id"].as_s
    @mc_name = json["name"].as_s

    {access_token: @access_token, uuid: @uuid, mc_name: @mc_name}
  end

  private def headers
    HTTP::Headers{
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
    }
  end
end
