require "../../src/rosegold"
require "../support/auth_http"

private def session_auth_packet(reused : Bool = false)
  request = Rosegold::Clientbound::EncryptionRequest.new("", "", Bytes.empty, true)
  Rosegold::Serverbound::EncryptionResponse.new(request, "00000000000000000000000000000000", "minecraft-spec", reused)
end

Spectator.describe "Minecraft session authentication" do
  let(directory) { File.join(Dir.tempdir, "rosegold-session-spec-#{Process.pid}-#{Random::Secure.hex(8)}") }

  before_each do
    AuthSpec.reset
    AuthSpec.directory = directory
    Dir.mkdir_p(directory)
    expect(Rosegold::Config.directory_for("auth")).to eq(directory)
    AuthSpec.token.save
    AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url) }
  end

  after_each do
    AuthSpec.reset
    FileUtils.rm_rf(directory)
  end

  it "invalidates cached 401 and 403 rejections and permits a fresh-token retry" do
    [401, 403].each do |status|
      AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url) }
      Minecraft::Auth.authenticate
      AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(status, "") }
      expect { session_auth_packet(true).send_join_request! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.phase).to eq("session_join")
        expect(error.refresh_cached_token?).to be_true
      }
      AuthSpec.transport = ->(_method : String, url : String) { AuthSpec.response(url) }
      expect(Minecraft::Auth.authenticate_with_cache_status[:reused]).to be_false
      AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(status, "") }
      expect { session_auth_packet.send_join_request! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.refresh_cached_token?).to be_false
      }
    end
  end

  it "honors Retry-After including zero instead of a fresh-token retry" do
    ["0", "20"].each do |retry_after|
      AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(401, "", HTTP::Headers{"Retry-After" => retry_after}) }
      expect { session_auth_packet(true).send_join_request! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.refresh_cached_token?).to be_false
        expect(error.retry_after).to eq(retry_after.to_i.seconds)
      }
    end
  end

  it "preserves rate-limit details" do
    AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(429, "", HTTP::Headers{"Retry-After" => "900"}) }
    expect { session_auth_packet(true).send_join_request! }.to raise_error(Minecraft::AuthenticationError) { |error|
      expect(error.phase).to eq("session_join")
      expect(error.status_code).to eq(429)
      expect(error.retry_after).to eq(15.minutes)
      expect(error.transient?).to be_true
      expect(error.refresh_cached_token?).to be_false
    }
  end

  it "turns transport failures into typed authentication failures" do
    [::IO::Error.new("private transport details"), OpenSSL::SSL::Error.allocate].each do |failure|
      AuthSpec.transport = ->(_method : String, _url : String) : HTTP::Client::Response { raise failure }
      expect { session_auth_packet.send_join_request! }.to raise_error(Minecraft::AuthenticationError) { |error|
        expect(error.phase).to eq("session_join")
        expect(error.transient?).to be_true
        expect(error.message).not_to contain("private")
      }
    end
  end

  it "accepts a successful join response" do
    AuthSpec.transport = ->(_method : String, _url : String) { HTTP::Client::Response.new(204) }
    expect { session_auth_packet.send_join_request! }.not_to raise_error
  end
end
