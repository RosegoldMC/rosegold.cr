require "http"
require "json"
require "../microsoft/mobile_oauth"

# Custom exception for authentication errors
class Minecraft::AuthenticationError < Exception
end

class Minecraft::Auth
  @xbox_token : String?
  @uhs : String?
  @xsts_token : String?
  @access_token : String?
  @uuid : String?
  @mc_name : String?
  @microsoft_token : String

  def initialize
    token = Microsoft::MobileOAuth.login!
    @microsoft_token = token.access_token
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
          "RpsTicket"  => "d=#{@microsoft_token}",
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

    # Check for authentication errors
    if json.as_h.has_key?("error")
      error_msg = json["error"].as_s
      if error_msg == "TOO_MANY_REQUESTS"
        raise AuthenticationError.new("Microsoft authentication rate limit exceeded. Please wait a few minutes before trying again.")
      else
        raise AuthenticationError.new("Microsoft authentication failed: #{error_msg}")
      end
    end

    unless json.as_h.has_key?("access_token")
      raise AuthenticationError.new("Microsoft authentication failed: No access token received. Response: #{json}")
    end

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
