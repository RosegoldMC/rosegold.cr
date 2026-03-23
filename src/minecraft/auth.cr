require "http"
require "json"
require "../microsoft/mobile_oauth"

class Minecraft::AuthenticationError < Exception
end

module Minecraft::Auth
  def self.authenticate : {access_token: String, uuid: String, mc_name: String}
    microsoft_token = Microsoft::MobileOAuth.login!.access_token
    xbox_token, uhs = xbox_authenticate(microsoft_token)
    xsts_token = xsts_authorize(xbox_token)
    access_token = login_with_xbox(uhs, xsts_token)
    uuid, mc_name = get_minecraft_profile(access_token)
    {access_token: access_token, uuid: uuid, mc_name: mc_name}
  end

  private def self.check_response(response, step : String)
    unless response.success?
      if response.status_code == 429
        raise AuthenticationError.new("Rate limit exceeded. Please wait a few minutes before trying again.")
      end
      begin
        json = JSON.parse(response.body)
        if xerr = json["XErr"]?
          raise AuthenticationError.new(xsts_error_message(xerr.as_i64))
        end
        error = (json["error"]? || json["Message"]?).try(&.as_s)
        raise AuthenticationError.new("#{step}: #{error}") if error
      rescue ex : JSON::ParseException
      end
      raise AuthenticationError.new("#{step} failed (HTTP #{response.status_code})")
    end
  end

  private def self.xsts_error_message(xerr : Int64) : String
    case xerr
    when 2148916227 then "This Xbox account has been banned. Visit https://enforcement.xbox.com/ for details."
    when 2148916229 then "This account is restricted by parental controls. A guardian must allow online play."
    when 2148916233 then "This account does not have an Xbox profile. Please create one at https://signup.live.com/"
    when 2148916234 then "This account has not accepted the Xbox Terms of Service. Please log in at https://xbox.com and accept them."
    when 2148916235 then "Xbox Live is not available in this country/region."
    when 2148916236 then "This account requires proof of age. Please log in at https://login.live.com/"
    when 2148916237 then "This account has reached the playtime limit. Contact account holder."
    when 2148916238 then "This is a child account that must be added to a Family by an adult. Visit https://account.microsoft.com/family"
    else                 "Xbox authentication failed (XErr: #{xerr})"
    end
  end

  private def self.xbox_authenticate(microsoft_token : String) : {String, String}
    response = HTTP::Client.post("https://user.auth.xboxlive.com/user/authenticate",
      headers: headers.merge!({"x-xbl-contract-version" => "2"}),
      body: {
        "Properties" => {
          "AuthMethod" => "RPS",
          "SiteName"   => "user.auth.xboxlive.com",
          "RpsTicket"  => "d=#{microsoft_token}",
        },
        "RelyingParty" => "http://auth.xboxlive.com",
        "TokenType"    => "JWT",
      }.to_json)

    check_response(response, "Xbox Live authentication")

    json = JSON.parse(response.body)
    token = json["Token"].as_s
    uhs = json["DisplayClaims"]["xui"].as_a.first["uhs"].as_s
    {token, uhs}
  end

  private def self.xsts_authorize(xbox_token : String) : String
    response = HTTP::Client.post("https://xsts.auth.xboxlive.com/xsts/authorize",
      headers: headers.merge!({"x-xbl-contract-version" => "1"}),
      body: {
        "Properties" => {
          "SandboxId"  => "RETAIL",
          "UserTokens" => [
            xbox_token,
          ],
        },
        "RelyingParty" => "rp://api.minecraftservices.com/",
        "TokenType"    => "JWT",
      }.to_json)

    check_response(response, "XSTS authorization")

    json = JSON.parse(response.body)
    json["Token"].as_s
  end

  private def self.login_with_xbox(uhs : String, xsts_token : String) : String
    response = HTTP::Client.post("https://api.minecraftservices.com/authentication/login_with_xbox",
      headers: headers,
      body: {
        "identityToken" => "XBL3.0 x=#{uhs};#{xsts_token}",
      }.to_json)

    check_response(response, "Minecraft authentication")

    json = JSON.parse(response.body)

    unless token = json["access_token"]?
      raise AuthenticationError.new("Minecraft authentication failed: no access token received")
    end

    token.as_s
  end

  private def self.get_minecraft_profile(access_token : String) : {String, String}
    response = HTTP::Client.get("https://api.minecraftservices.com/minecraft/profile",
      headers: headers.merge!({"Authorization" => "Bearer #{access_token}"}))

    check_response(response, "Minecraft profile")

    json = JSON.parse(response.body)

    unless id = json["id"]?
      error = json["error"]?.try(&.as_s)
      if error == "NOT_FOUND"
        raise AuthenticationError.new("This account does not own Minecraft Java Edition. Purchase at https://minecraft.net")
      elsif error
        raise AuthenticationError.new("Minecraft profile error: #{error}")
      end
      raise AuthenticationError.new("This account does not own Minecraft Java Edition. Purchase at https://minecraft.net")
    end

    unless name = json["name"]?
      raise AuthenticationError.new("Minecraft profile missing username")
    end

    {id.as_s, name.as_s}
  end

  private def self.headers
    HTTP::Headers{
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
    }
  end
end
