require "../spec_helper"

Spectator.describe Rosegold::Proxy::Server do
  it "can be created with default port" do
    server = Rosegold::Proxy::Server.new
    expect(server.port).to eq(25566)
    expect(server.locked_out).to be_false
  end

  it "can be created with custom port" do
    server = Rosegold::Proxy::Server.new(12345)
    expect(server.port).to eq(12345)
  end

  it "can lock out and unlock connections" do
    server = Rosegold::Proxy::Server.new
    
    server.lock_out
    expect(server.locked_out).to be_true
    
    server.unlock
    expect(server.locked_out).to be_false
  end

  it "requires bot client to start" do
    server = Rosegold::Proxy::Server.new
    expect { server.start }.to raise_error("No bot client attached")
  end

  it "can attach a bot client" do
    server = Rosegold::Proxy::Server.new
    client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
    
    server.attach_bot(client)
    # Should not raise when starting now (though it won't actually start without a connection)
  end
end