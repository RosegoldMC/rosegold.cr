require "http/client"
require "json"
require "uri"
require "../rosegold/config"
require "../minecraft/authentication_error"

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

    def refresh(on_success : Proc(String, Nil)? = nil)
      if expired?
        refresh!(on_success)
      else
        self
      end
    end

    def refresh!(on_success : Proc(String, Nil)? = nil)
      response = HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access&refresh_token=#{URI.encode_www_form(refresh_token)}&grant_type=refresh_token"
      )
      unless response.success?
        error = begin
          JSON.parse(response.body)["error"]?.try(&.as_s?)
        rescue JSON::ParseException | TypeCastError
          nil
        end
        invalid = response.status_code == 400 && {"invalid_grant", "interaction_required"}.includes?(error)
        failure = Minecraft::AuthenticationError.from_response("microsoft_refresh", response, "Microsoft token refresh failed")
        failure.transient = !invalid
        raise failure
      end
      Token.from_json(response.body).tap do |token|
        token.expires_at = Time.local.to_unix + token.expires_in
        token.save
        on_success.try &.call("microsoft_refresh")
      end
    rescue ex : Minecraft::AuthenticationError
      raise ex
    rescue ex : File::Error
      raise ex
    rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError
      raise Minecraft::AuthenticationError.new("Microsoft token refresh is temporarily unavailable", phase: "microsoft_refresh", transient: true)
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

  def self.login!(on_success : Proc(String, Nil)? = nil) : Token
    if File.exists?(Rosegold::Config.directory_for("auth") + "/microsoft_token.json")
      token = begin
        Token.load
      rescue ex : JSON::ParseException | File::NotFoundError
        nil
      end
      if token
        begin
          return token.refresh(on_success)
        rescue ex : Minecraft::AuthenticationError
          raise ex if ex.transient?
        end
      end
    end
    prompt_for_login!(on_success).tap &.save
  end

  # Prompts the user to follow Microsoft's Device Flow for OAuth.
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-device-code
  def self.prompt_for_login!(on_success : Proc(String, Nil)? = nil) : Token
    response = HTTP::Client.post(
      "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
      form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access"
    )
    unless response.success?
      raise Minecraft::AuthenticationError.from_response("microsoft_device", response, "Microsoft device login failed")
    end
    device_response = JSON.parse(response.body)

    STDERR.puts device_response["message"]

    device_code = device_response["device_code"].as_s
    interval = (device_response["interval"]?.try(&.as_i) || 5).seconds
    expires_in = device_response["expires_in"]?.try(&.as_i) || 600
    deadline = Time.instant + expires_in.seconds

    loop do
      if Time.instant >= deadline
        raise Minecraft::AuthenticationError.new("Device code expired. Please try again.", phase: "microsoft_device")
      end

      sleep interval

      response = HTTP::Client.post(
        "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
        form: "client_id=#{CLIENT_ID}&scope=XboxLive.signin+offline_access&device_code=#{URI.encode_www_form(device_code)}&grant_type=urn:ietf:params:oauth:grant-type:device_code"
      )

      if response.status_code == 429 || response.status_code >= 500
        raise Minecraft::AuthenticationError.from_response("microsoft_device", response, "Microsoft device login is temporarily unavailable")
      end

      token_string = response.body
      json = JSON.parse(token_string)

      if error = json["error"]?.try(&.as_s)
        case error
        when "authorization_pending"
          next
        when "slow_down"
          interval += 5.seconds
          next
        when "access_denied", "authorization_declined"
          raise Minecraft::AuthenticationError.new("User declined authorization.", phase: "microsoft_device")
        when "expired_token"
          raise Minecraft::AuthenticationError.new("Device code expired. Please try again.", phase: "microsoft_device")
        else
          raise Minecraft::AuthenticationError.from_response("microsoft_device", response, "Microsoft device login was rejected")
        end
      end

      unless response.success?
        raise Minecraft::AuthenticationError.from_response("microsoft_device", response, "Microsoft device login failed")
      end

      token = Token.from_json(token_string)
      token.expires_at = Time.local.to_unix + token.expires_in

      STDERR.puts "Login successful!"

      on_success.try &.call("microsoft_device")
      return token
    end
  rescue ex : Minecraft::AuthenticationError
    raise ex
  rescue ex : ::IO::Error | Socket::Error | OpenSSL::SSL::Error | JSON::ParseException | TypeCastError | KeyError
    raise Minecraft::AuthenticationError.new("Microsoft device login is temporarily unavailable", phase: "microsoft_device", transient: true)
  end
end
