require "../spec_helper"

# Test helper: inject an in-memory connection so send_packet! can be exercised
# without a real server.
module Rosegold
  class Client
    def inject_test_connection(conn : Connection::Client)
      @connection = conn
    end
  end
end

# Regression: on a Velocity server switch (e.g. CivMC queue→main via ajqueue)
# the server sends StartConfiguration and we flip to CONFIGURATION. Vanilla
# stops ticking during configuration; sending a PLAY packet (ClientTickEnd,
# serverbound 0x0C) while the proxy has us in CONFIGURATION is decoded as an
# unknown config packet and the proxy drops us with "An internal error
# occurred in your connection."
Spectator.describe "Server switch PLAY/CONFIGURATION packet gating" do
  def build_client(state : Rosegold::ProtocolState)
    io = Minecraft::IO::Memory.new
    conn = Rosegold::Connection::Client.new(io, state, Rosegold::Client.protocol_version)
    client = Rosegold::Client.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "test"})
    client.inject_test_connection(conn)
    client.set_protocol_state(state)
    {client, io}
  end

  it "drops a PLAY packet (ClientTickEnd) while in CONFIGURATION state" do
    client, io = build_client(Rosegold::ProtocolState::CONFIGURATION)
    client.send_packet!(Rosegold::Serverbound::ClientTickEnd.new)
    expect(io.size).to eq(0)
  end

  it "still sends CONFIGURATION packets while in CONFIGURATION state" do
    client, io = build_client(Rosegold::ProtocolState::CONFIGURATION)
    client.send_packet!(Rosegold::Serverbound::FinishConfiguration.new)
    expect(io.size).to be > 0
  end

  it "sends PLAY packets normally while in PLAY state" do
    client, io = build_client(Rosegold::ProtocolState::PLAY)
    client.send_packet!(Rosegold::Serverbound::ClientTickEnd.new)
    expect(io.size).to be > 0
  end
end
