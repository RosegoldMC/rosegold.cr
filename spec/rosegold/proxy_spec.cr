require "../spec_helper"

Spectator.describe Rosegold::Proxy do
  describe "initialization" do
    it "creates a proxy with default settings" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
      proxy = Rosegold::Proxy.new(client)
      
      expect(proxy.client).to eq(client)
      expect(proxy.host).to eq("localhost")
      expect(proxy.port).to eq(25566)
      expect(proxy.locked).to be_false
      expect(proxy.connected_clients).to be_empty
    end

    it "creates a proxy with custom host and port" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
      proxy = Rosegold::Proxy.new(client, "127.0.0.1", 25567)
      
      expect(proxy.host).to eq("127.0.0.1")
      expect(proxy.port).to eq(25567)
    end
  end

  describe "server management" do
    it "handles locking and unlocking" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
      proxy = Rosegold::Proxy.new(client)
      
      expect(proxy.locked).to be_false
      
      proxy.lock
      expect(proxy.locked).to be_true
      
      proxy.unlock
      expect(proxy.locked).to be_false
    end
  end

  describe "client integration" do
    it "can be started from a client" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
      
      expect(client.proxy?).to be_nil
      
      # We don't actually start the server here to avoid port conflicts in tests
      proxy = Rosegold::Proxy.new(client, "localhost", 25568)
      
      expect(proxy).to be_a(Rosegold::Proxy)
      expect(proxy.client).to eq(client)
    end
  end
end