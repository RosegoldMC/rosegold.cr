require "http/client"
require "json"
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
      HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin offline_access&refresh_token=#{refresh_token}&grant_type=refresh_token"
      ).body
        .try do |json|
          Token.from_json(json).tap do |token|
            token.expires_at = Time.local.to_unix + token.expires_in
            token.save
          end
        end
    end

    def expired?
      Time.local.to_unix > expires_at
    end

    def self.load
      Token.from_json(File.read(Rosegold::Config.directory_for("auth") + "/microsoft_token.json"))
    end

    def save
      File.write(Rosegold::Config.directory_for("auth") + "/microsoft_token.json", to_json)
    end
  end

  def self.login! : Token
    if File.exists?(Rosegold::Config.directory_for("auth") + "/microsoft_token.json")
      Token.load.refresh
    else
      prompt_for_login!.tap &.save
    end
  end

  # Prompts the user to follow Microsoft's Device Flow for OAuth.
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-device-code
  # Returns the access token as a String
  def self.prompt_for_login! : Token
    JSON.parse(
      HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin offline_access"
      ).body
    ).try do |json|
      STDERR.puts json["message"]

      loop do
        sleep 5
        HTTP::Client.post(
          "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
          form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin offline_access&code=#{json["device_code"]}&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        ).body.try do |token_string|
          next if JSON.parse(token_string)["error"]?

          token = Token.from_json(token_string)
          token.expires_at = Time.local.to_unix + token.expires_in

          STDERR.puts "Login successful!"

          return token
        end
      end
    end
  end
end
