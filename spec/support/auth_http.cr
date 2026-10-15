require "../../src/minecraft/auth"
require "spectator"
require "file_utils"

module AuthSpec
  class_property instant : Time::Instant?
  class_property directory : String?
  class_property transport : Proc(String, String, HTTP::Client::Response)?
  class_property requests = [] of String

  def self.request(method : String, url : String)
    requests << url
    handler = transport || raise "Authentication HTTP fixture is missing"
    handler.call(method, url)
  end

  def self.reset
    self.instant = nil
    self.directory = nil
    self.transport = nil
    requests.clear
    Minecraft::Auth.clear_cache
  end

  def self.token
    Microsoft::MobileOAuth::Token.from_json(%({"token_type":"Bearer","scope":"XboxLive.signin","expires_in":3600,"ext_expires_in":3600,"access_token":"microsoft-spec","refresh_token":"refresh-spec","expires_at":4102444800}))
  end

  def self.response(url : String, expires_in : Int32? = 120)
    body = case url
           when "https://user.auth.xboxlive.com/user/authenticate"
             %({"Token":"xbox-spec","DisplayClaims":{"xui":[{"uhs":"uhs-spec"}]}})
           when "https://xsts.auth.xboxlive.com/xsts/authorize"
             %({"Token":"xsts-spec"})
           when "https://api.minecraftservices.com/authentication/login_with_xbox"
             {"access_token" => "minecraft-spec", "expires_in" => expires_in}.to_json
           when "https://api.minecraftservices.com/minecraft/profile"
             %({"id":"00000000000000000000000000000000","name":"Spec"})
           else
             raise "Unexpected authentication URL"
           end
    HTTP::Client::Response.new(200, body)
  end
end

struct Time
  def self.instant : Time::Instant
    AuthSpec.instant || previous_def
  end
end

class Rosegold::Config
  def self.directory_for(service : String)
    AuthSpec.directory || previous_def
  end
end

class HTTP::Client
  def self.exec(method : String, url : String | URI, headers : HTTP::Headers? = nil, body : BodyType = nil, tls : TLSContext = nil) : HTTP::Client::Response
    return AuthSpec.request(method, url.to_s) if AuthSpec.transport
    previous_def
  end

  def self.post(url, headers : HTTP::Headers? = nil, tls : TLSContext = nil, *, form : String | ::IO | Hash) : HTTP::Client::Response
    return AuthSpec.request("POST", url.to_s) if AuthSpec.transport
    previous_def
  end
end
