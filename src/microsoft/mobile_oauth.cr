require "http/client"
require "json"
require "uri"
require "../rosegold/config"

module Microsoft::MobileOAuth
  CLIENT_ID = "e550efe8-765e-41aa-a7cf-9bcaaa82d2b9"

  class Token
    include JSON::Serializable

    property \
      token_type : String,
      scope : String,
      expires_in : Int32,
      ext_expires_in : Int32,
      access_token : String,
      refresh_token : String,
      expires_at : Int64 = 0

    def refresh
      if expired?
        refresh!
      else
        self
      end
    end

    def refresh!
      response = HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access&refresh_token=#{URI.encode_www_form(refresh_token)}&grant_type=refresh_token"
      ).body
      json = JSON.parse(response)
      if error = json["error"]?.try(&.as_s)
        raise "Token refresh failed: #{json["error_description"]?.try(&.as_s) || error}"
      end
      Token.from_json(response).tap do |token|
        token.expires_at = Time.local.to_unix + token.expires_in
        token.save
      end
    end

    def expired?
      Time.local.to_unix > expires_at - 60
    end

    def self.load
      Token.from_json(File.read(Rosegold::Config.directory_for("auth") + "/microsoft_token.json"))
    end

    def save
      path = Rosegold::Config.directory_for("auth") + "/microsoft_token.json"
      File.write(path, to_json)
      File.chmod(path, 0o600)
    end
  end

  def self.login! : Token
    if File.exists?(Rosegold::Config.directory_for("auth") + "/microsoft_token.json")
      begin
        return Token.load.refresh
      rescue ex
        STDERR.puts ex.message
        STDERR.puts "Requesting new login..."
      end
    end
    prompt_for_login!.tap &.save
  end

  # Prompts the user to follow Microsoft's Device Flow for OAuth.
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-device-code
  # Returns the access token as a String
  def self.prompt_for_login! : Token
    device_response = JSON.parse(
      HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access"
      ).body
    )

    STDERR.puts device_response["message"]

    device_code = device_response["device_code"].as_s
    interval = (device_response["interval"]?.try(&.as_i) || 5).seconds
    expires_in = device_response["expires_in"]?.try(&.as_i) || 600
    deadline = Time.monotonic + expires_in.seconds

    loop do
      raise "Device code expired. Please try again." if Time.monotonic >= deadline

      sleep interval

      token_string = HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access&device_code=#{URI.encode_www_form(device_code)}&grant_type=urn:ietf:params:oauth:grant-type:device_code"
      ).body

      json = JSON.parse(token_string)

      if error = json["error"]?.try(&.as_s)
        case error
        when "authorization_pending"
          next
        when "slow_down"
          interval += 5.seconds
          next
        when "access_denied", "authorization_declined"
          raise "User declined authorization."
        when "expired_token"
          raise "Device code expired. Please try again."
        else
          description = json["error_description"]?.try(&.as_s) || error
          raise "Authentication failed: #{description}"
        end
      end

      token = Token.from_json(token_string)
      token.expires_at = Time.local.to_unix + token.expires_in

      STDERR.puts "Login successful!"

      return token
    end
  end
end
