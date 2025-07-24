require "../spec_helper"

Spectator.describe "Proxy Integration" do
  it "allows basic proxy connection" do
    # This is a basic integration test that demonstrates the proxy concept
    # In a real integration test, we would connect to an actual Minecraft server
    
    # Create a bot client (would normally connect to actual server)
    bot_client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000001", username: "testbot"})
    
    # Start proxy server
    proxy = bot_client.start_proxy("localhost", 25567)
    
    expect(proxy).not_to be_nil
    if proxy
      expect(proxy.client).to eq(bot_client)
      expect(proxy.host).to eq("localhost")
      expect(proxy.port).to eq(25567)
      
      # Verify the proxy can be locked and unlocked
      proxy.lock
      expect(proxy.locked).to be_true
      
      proxy.unlock
      expect(proxy.locked).to be_false
    end
    
    # Stop the proxy
    bot_client.stop_proxy
    expect(bot_client.proxy?).to be_nil
  end
  
  skip "connects two rosegold clients via proxy" do
    # This would be a more comprehensive test that:
    # 1. Creates a bot that connects to a mock/test server
    # 2. Starts the proxy
    # 3. Creates a second rosegold client that connects to the proxy
    # 4. Verifies that packets are forwarded correctly
    
    # For now, this is marked as pending since it requires more infrastructure
    # to set up mock server connections and proper packet forwarding tests
  end
end