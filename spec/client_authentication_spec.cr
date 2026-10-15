require "./spec_helper"

class AuthenticationProbeClient < Rosegold::Client
  getter authentication_calls = 0

  private def detect_protocol_version
  end

  private def authenticate!
    @authentication_calls += 1
    raise Minecraft::AuthenticationError.new("Authentication unavailable", phase: "xbox_live", transient: true)
  end
end

class ReaderAuthenticationFailureClient < Rosegold::Client
  private def detect_protocol_version
  end

  private def authenticate!
    player.uuid = UUID.new("00000000-0000-0000-0000-000000000000")
    player.username = "Test"
  end

  private def read_packet
    raise Minecraft::AuthenticationError.new("Session rate limited", phase: "session_join", status_code: 429, retry_after: 7.minutes, transient: true)
  end
end

Spectator.describe "Client authentication lifecycle" do
  it "does not authenticate when the server TCP port is unavailable" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    server.close
    bot_client = AuthenticationProbeClient.new("127.0.0.1", port)

    expect { bot_client.connect }.to raise_error(Socket::ConnectError)
    expect(bot_client.authentication_calls).to eq(0)
  end

  it "closes its reachability probe before starting authentication" do
    server = TCPServer.new("127.0.0.1", 0)
    bot_client = AuthenticationProbeClient.new("127.0.0.1", server.local_address.port)

    expect { bot_client.connect }.to raise_error(Minecraft::AuthenticationError)
    expect(bot_client.authentication_calls).to eq(1)
    peer = server.accept
    peer.read_timeout = 1.second
    expect(peer.read_byte).to be_nil
    expect(bot_client.connected?).to be_falsey
  ensure
    peer.try &.close
    server.try &.close
  end

  it "propagates a reader authentication failure through join_game" do
    server = TCPServer.new("127.0.0.1", 0)
    bot_client = ReaderAuthenticationFailureClient.new("127.0.0.1", server.local_address.port)

    expect { bot_client.join_game }.to raise_error(Minecraft::AuthenticationError, "Session rate limited")
    expect(bot_client.authentication_failure.try(&.status_code)).to eq(429)
    expect(bot_client.authentication_failure.try(&.retry_after)).to eq(7.minutes)
    expect(bot_client.connected?).to be_falsey
  ensure
    bot_client.try &.connection?.try &.disconnect("Test finished")
    server.try &.close
  end
end
