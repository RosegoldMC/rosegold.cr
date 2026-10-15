require "../support/auth_http"

Spectator.describe Microsoft::MobileOAuth do
  let(directory) { File.join(Dir.tempdir, "rosegold-oauth-spec-#{Process.pid}-#{Random::Secure.hex(8)}") }

  before_each do
    AuthSpec.reset
    Dir.mkdir_p(directory)
    AuthSpec.directory = directory
  end

  after_each do
    AuthSpec.reset
    FileUtils.rm_rf(directory)
  end

  it "preserves transient refresh failures without starting device login" do
    token = AuthSpec.token
    token.expires_at = 0
    token.save
    [429, 500].each do |status|
      AuthSpec.requests.clear
      AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(status, "not JSON", HTTP::Headers{"Retry-After" => "4"}) }
      expect { Microsoft::MobileOAuth.login! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.phase).to eq("microsoft_refresh")
        expect(error.transient?).to be_true
        expect(error.retry_after).to eq(4.seconds)
      }
      expect(AuthSpec.requests.size).to eq(1)
      expect(AuthSpec.requests.first.ends_with?("/token")).to be_true
      expect(Microsoft::MobileOAuth::Token.load.refresh_token).to eq("refresh-spec")
    end
  end

  it "requests device login only after an explicit invalid refresh grant" do
    token = AuthSpec.token
    token.expires_at = 0
    token.save
    AuthSpec.transport = ->(_method : String, url : String) {
      if url.ends_with?("/devicecode")
        HTTP::Client::Response.new(429, "", HTTP::Headers{"Retry-After" => "9"})
      else
        HTTP::Client::Response.new(400, %({"error":"invalid_grant"}))
      end
    }
    expect { Microsoft::MobileOAuth.login! }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("microsoft_device")
      expect(error.retry_after).to eq(9.seconds)
    }
    expect(AuthSpec.requests.size).to eq(2)
  end

  it "preserves TLS refresh failures without starting device login" do
    token = AuthSpec.token
    token.expires_at = 0
    token.save
    AuthSpec.transport = ->(_method : String, _url : String) : HTTP::Client::Response { raise OpenSSL::SSL::Error.allocate }
    expect { Microsoft::MobileOAuth.login! }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("microsoft_refresh")
      expect(error.transient?).to be_true
      expect(error.message).not_to contain("private")
    }
    expect(AuthSpec.requests.size).to eq(1)
  end

  it "records a refreshed token only after parsing and saving it" do
    phases = [] of String
    AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(200, AuthSpec.token.to_json) }
    handler = ->(phase : String) { phases << phase; nil }
    AuthSpec.token.refresh!(handler)
    expect(phases).to eq(["microsoft_refresh"])
    expect(Microsoft::MobileOAuth::Token.load.access_token).to eq("microsoft-spec")
  end

  it "keeps malformed refresh success typed and does not prompt" do
    token = AuthSpec.token
    token.expires_at = 0
    token.save
    AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(200, "{}") }
    expect { Microsoft::MobileOAuth.login! }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("microsoft_refresh")
      expect(error.transient?).to be_true
    }
    expect(AuthSpec.requests.size).to eq(1)
  end

  it "propagates token save failures without prompting again" do
    token = AuthSpec.token
    token.expires_at = 0
    token.save
    AuthSpec.transport = ->(_method : String, _url : String) {
      AuthSpec.directory = File.join(directory, "missing")
      HTTP::Client::Response.new(200, AuthSpec.token.to_json)
    }
    expect { Microsoft::MobileOAuth.login! }.to raise_error(File::Error)
    expect(AuthSpec.requests.size).to eq(1)
  end

  it "preserves device polling rate limits and service failures" do
    [429, 503].each do |status|
      AuthSpec.transport = ->(_method : String, url : String) {
        if url.ends_with?("/devicecode")
          HTTP::Client::Response.new(200, %({"message":"Spec authorization","device_code":"spec-code","interval":0,"expires_in":60}))
        else
          HTTP::Client::Response.new(status, "not JSON", HTTP::Headers{"Retry-After" => "7"})
        end
      }
      expect { Microsoft::MobileOAuth.prompt_for_login! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.phase).to eq("microsoft_device")
        expect(error.status_code).to eq(status)
        expect(error.retry_after).to eq(7.seconds)
        expect(error.transient?).to be_true
      }
    end
  end

  it "keeps explicit device denial terminal" do
    AuthSpec.transport = ->(_method : String, url : String) {
      if url.ends_with?("/devicecode")
        HTTP::Client::Response.new(200, %({"message":"Spec authorization","device_code":"spec-code","interval":0,"expires_in":60}))
      else
        HTTP::Client::Response.new(400, %({"error":"access_denied","error_description":"private provider text"}))
      end
    }
    expect { Microsoft::MobileOAuth.prompt_for_login! }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("microsoft_device")
      expect(error.transient?).to be_false
      expect(error.message).to eq("User declined authorization.")
    }
  end
end
