require "http"
require "json"
require "./authentication_error"
require "../microsoft/mobile_oauth"

module Minecraft::Auth
  alias Authentication = NamedTuple(access_token: String, uuid: String, mc_name: String)
  alias SuccessHandler = Proc(String, Nil)

  private record CacheEntry, auth : Authentication, expires_at : Time::Instant

  @@cache = {} of String => CacheEntry
  @@cache_mutex = Mutex.new

  def self.authenticate : Authentication
    authenticate_with_cache_status[:auth]
  end

  def self.authenticate_with_cache_status(on_success : SuccessHandler? = nil)
    directory = Rosegold::Config.directory_for("auth")
    @@cache_mutex.synchronize do
      if entry = @@cache[directory]?
        return {auth: entry.auth, reused: true} if Time.instant < entry.expires_at
        @@cache.delete(directory)
      end

      microsoft_token = Microsoft::MobileOAuth.login!(on_success).access_token
      xbox_token, uhs = xbox_authenticate(microsoft_token, on_success)
      xsts_token = xsts_authorize(xbox_token, on_success)
      token = login_with_xbox(uhs, xsts_token, on_success)
      access_token = token[:access_token]
      uuid, mc_name = get_minecraft_profile(access_token, on_success)
      auth = {access_token: access_token, uuid: uuid, mc_name: mc_name}
      if expires_at = token[:expires_at]
        @@cache[directory] = CacheEntry.new(auth, expires_at) if expires_at > Time.instant
      end
      {auth: auth, reused: false}
    end
  end

  def self.clear_cache : Nil
    @@cache_mutex.synchronize { @@cache.clear }
    nil
  end

  def self.invalidate_access_token(token : String) : Nil
    @@cache_mutex.synchronize do
      @@cache.reject! { |_directory, entry| entry.auth[:access_token] == token }
    end
    nil
  end

  def self.failure(phase : String, response : HTTP::Client::Response, message : String)
    AuthenticationError.from_response(phase, response, message)
  end

  private def self.check_response(response, step : String)
    unless response.success?
      if response.status_code == 429
        raise failure(step, response, "#{step} is rate limited")
      end
      begin
        json = JSON.parse(response.body)
        if xerr = json["XErr"]?
          raise failure(step, response, xsts_error_message(xerr.as_i64))
        end
        raise failure(step, response, "#{step} was rejected") if json["error"]? || json["Message"]?
      rescue ex : JSON::ParseException | TypeCastError | KeyError
      end
      raise failure(step, response, "#{step} failed (HTTP #{response.status_code})")
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

  private def self.xbox_authenticate(microsoft_token : String, on_success : SuccessHandler?) : {String, String}
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

    check_response(response, "xbox_live")

    json = JSON.parse(response.body)
    token = json["Token"].as_s
    uhs = json["DisplayClaims"]["xui"].as_a.first["uhs"].as_s
    on_success.try &.call("xbox_live")
    {token, uhs}
  rescue ex : AuthenticationError
    raise ex
  rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError | IndexError
    raise AuthenticationError.new("Xbox Live authentication is temporarily unavailable", phase: "xbox_live", transient: true)
  end

  private def self.xsts_authorize(xbox_token : String, on_success : SuccessHandler?) : String
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

    check_response(response, "xsts")

    token = JSON.parse(response.body)["Token"].as_s
    on_success.try &.call("xsts")
    token
  rescue ex : AuthenticationError
    raise ex
  rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError | IndexError
    raise AuthenticationError.new("XSTS authorization is temporarily unavailable", phase: "xsts", transient: true)
  end

  private def self.login_with_xbox(uhs : String, xsts_token : String, on_success : SuccessHandler?)
    response = HTTP::Client.post("https://api.minecraftservices.com/authentication/login_with_xbox",
      headers: headers,
      body: {
        "identityToken" => "XBL3.0 x=#{uhs};#{xsts_token}",
      }.to_json)

    check_response(response, "minecraft_login")

    issued_at = Time.instant
    json = JSON.parse(response.body)

    unless token = json["access_token"]?.try(&.as_s?)
      raise AuthenticationError.new("Minecraft authentication returned no access token", phase: "minecraft_login")
    end

    # Leave time for in-flight login and session requests.
    expires_at = json["expires_in"]?.try(&.as_i?).try { |seconds| issued_at + seconds.seconds - 60.seconds }
    on_success.try &.call("minecraft_login")
    {access_token: token, expires_at: expires_at}
  rescue ex : AuthenticationError
    raise ex
  rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError | IndexError
    raise AuthenticationError.new("Minecraft authentication is temporarily unavailable", phase: "minecraft_login", transient: true)
  end

  private def self.get_minecraft_profile(access_token : String, on_success : SuccessHandler?) : {String, String}
    response = HTTP::Client.get("https://api.minecraftservices.com/minecraft/profile",
      headers: headers.merge!({"Authorization" => "Bearer #{access_token}"}))

    check_response(response, "minecraft_profile")

    json = JSON.parse(response.body)

    unless id = json["id"]?.try(&.as_s?)
      raise AuthenticationError.new("This account does not own Minecraft Java Edition. Purchase at https://minecraft.net", phase: "minecraft_profile")
    end

    unless name = json["name"]?.try(&.as_s?)
      raise AuthenticationError.new("Minecraft profile missing username", phase: "minecraft_profile")
    end

    on_success.try &.call("minecraft_profile")
    {id, name}
  rescue ex : AuthenticationError
    raise ex
  rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError | IndexError
    raise AuthenticationError.new("Minecraft profile is temporarily unavailable", phase: "minecraft_profile", transient: true)
  end

  private def self.headers
    HTTP::Headers{
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
    }
  end
end
