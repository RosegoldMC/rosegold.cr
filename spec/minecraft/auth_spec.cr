require "../support/auth_http"

Spectator.describe Minecraft::Auth do
  let(directory) { File.join(Dir.tempdir, "rosegold-auth-spec-#{Process.pid}-#{Random::Secure.hex(8)}") }

  before_each do
    Minecraft::Auth.clear_cache
    AuthSpec.directory = directory
    Dir.mkdir_p(directory)
    expect(Rosegold::Config.directory_for("auth")).to eq(directory)
    AuthSpec.token.save
    AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url) }
  end

  after_each do
    AuthSpec.reset
    FileUtils.rm_rf(directory)
    FileUtils.rm_rf(directory + "-other")
  end

  it "reuses authentication across concurrent callers" do
    AuthSpec.transport = ->(_method : String, url : String) { Fiber.yield; AuthSpec.response(url) }
    done = Channel(Minecraft::Auth::Authentication | Exception).new(2)
    2.times do
      spawn do
        done.send Minecraft::Auth.authenticate
      rescue error
        done.send error
      end
    end
    2.times do
      result = done.receive
      raise result if result.is_a?(Exception)
      expect(result[:access_token]).to eq("minecraft-spec")
    end
    expect(AuthSpec.requests.count(&.ends_with?("/minecraft/profile"))).to eq(1)
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_true
  end

  it "expires cached authentication sixty seconds before token expiry using monotonic time" do
    now = Time.instant
    AuthSpec.instant = now
    Minecraft::Auth.authenticate
    now += 59.seconds
    AuthSpec.instant = now
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_true
    now += 1.second
    AuthSpec.instant = now
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false
    expect(AuthSpec.requests.count(&.ends_with?("/minecraft/profile"))).to eq(2)
  end

  it "does not cache tokens with missing or short expiry" do
    [nil, 60, -1].each do |expires_in|
      Minecraft::Auth.clear_cache
      AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url, expires_in) }
      2.times { expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false }
    end
  end

  it "invalidates a rejected access token" do
    Minecraft::Auth.authenticate
    Minecraft::Auth.invalidate_access_token("minecraft-spec")
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false
  end

  it "keeps cached authentication separate for each auth directory" do
    Minecraft::Auth.authenticate
    other_directory = directory + "-other"
    AuthSpec.directory = other_directory
    Dir.mkdir_p(other_directory)
    AuthSpec.token.save
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false
  end

  it "records successful phases only after their replies validate" do
    phases = [] of String
    handler = ->(phase : String) { phases << phase; nil }
    Minecraft::Auth.authenticate_with_cache_status(handler)
    expect(phases).to eq(["xbox_live", "xsts", "minecraft_login", "minecraft_profile"])
    phases.clear
    Minecraft::Auth.authenticate_with_cache_status(handler)
    expect(phases).to be_empty
  end

  it "does not cache a failed profile request and reports no profile success" do
    phases = [] of String
    handler = ->(phase : String) { phases << phase; nil }
    AuthSpec.transport = ->(method : String, url : String) { method == "GET" ? HTTP::Client::Response.new(200, "not JSON") : AuthSpec.response(url) }
    expect { Minecraft::Auth.authenticate_with_cache_status(handler) }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("minecraft_profile")
      expect(error.transient?).to be_true
    }
    expect(phases).to eq(["xbox_live", "xsts", "minecraft_login"])
    AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url) }
    expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false
  end

  it "retains rate-limit details without provider response bodies" do
    AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(429, "sensitive provider response", HTTP::Headers{"Retry-After" => "12"}) }
    expect { Minecraft::Auth.authenticate }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("xbox_live")
      expect(error.status_code).to eq(429)
      expect(error.retry_after).to eq(12.seconds)
      expect(error.transient?).to be_true
      expect(error.message).not_to contain("sensitive")
    }
  end

  it "parses HTTP-date Retry-After and ignores malformed or elapsed values" do
    response = HTTP::Client::Response.new(429, nil, HTTP::Headers{"Retry-After" => HTTP.format_time(Time.utc + 2.minutes)})
    delay = Minecraft::AuthenticationError.retry_after(response) || raise "Missing Retry-After delay"
    expect(delay).to be > 119.seconds
    expect(delay).to be <= 2.minutes
    ["tomorrow", "-1", HTTP.format_time(Time.utc - 1.minute)].each do |value|
      response.headers["Retry-After"] = value
      expect(Minecraft::AuthenticationError.retry_after(response)).to be_nil
    end
    response.headers["Retry-After"] = "0"
    expect(Minecraft::AuthenticationError.retry_after(response)).to eq(0.seconds)
  end
end
