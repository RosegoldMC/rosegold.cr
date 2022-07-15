require "http/client"
require "json"

module Microsoft::MobileOAuth
  CLIENT_ID = "e550efe8-765e-41aa-a7cf-9bcaaa82d2b9"

  # Prompts the user to follow Microsoft's Device Flow for OAuth.
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-device-code
  # Returns the access token as a String
  def self.prompt_for_login! : String
    JSON.parse(
      HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin offline_access"
      ).body
    ).try do |json|
      STDERR.puts json["message"]

      loop do
        sleep 5
        JSON.parse(
          HTTP::Client.post(
            "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
            form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin offline_access&code=#{json["device_code"]}&grant_type=urn:ietf:params:oauth:grant-type:device_code"
          ).body).try do |token|
          next if token["error"]?

          STDERR.puts "Login successful!"

          return token["access_token"].as_s
        end
      end
    end
  end
end
