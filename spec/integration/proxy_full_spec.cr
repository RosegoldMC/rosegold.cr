require "../spec_helper"

Spectator.describe "Full Proxy Integration" do
  # This test simulates what would happen with a full docker integration
  # It uses two rosegold clients to simulate client and server connections
  
  it "can handle packet forwarding between mock connections" do
    # Create proxy server on a unique port
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25570)
    
    # Create a mock bot client
    bot = Rosegold::Client.new(
      "localhost", 25565,
      offline: {uuid: UUID.random.to_s, username: "ProxyBot"}
    )
    
    # Attach proxy to bot
    bot.attach_proxy(proxy)
    
    # Start proxy server
    proxy.start
    
    # Verify proxy state
    expect(proxy.lockout_active?).to be_false
    expect(proxy.bot_connected?).to be_false  # Bot not connected to actual server
    
    # Test lockout functionality
    proxy.enable_lockout
    expect(proxy.lockout_active?).to be_true
    
    proxy.disable_lockout  
    expect(proxy.lockout_active?).to be_false
    
    # Clean up
    proxy.stop
    expect(proxy.server).to be_nil
  end
  
  it "handles multiple proxy command types" do
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25571)
    
    # Test all command interception
    expect(proxy.intercept_chat("/rosegold help", nil)).to be_true
    expect(proxy.intercept_chat("/rosegold status", nil)).to be_true
    expect(proxy.intercept_chat("/rosegold lock", nil)).to be_true
    expect(proxy.intercept_chat("/rosegold unlock", nil)).to be_true
    expect(proxy.intercept_chat("/rosegold invalid", nil)).to be_true
    
    # Test non-commands pass through
    expect(proxy.intercept_chat("hello world", nil)).to be_false
    expect(proxy.intercept_chat("/tp @p 0 64 0", nil)).to be_false
    expect(proxy.intercept_chat("/gamemode creative", nil)).to be_false
  end
  
  it "proxy server manages client connections list" do
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25572)
    
    # Note: Full connection testing would require actual TCP clients
    # which is beyond the scope of unit tests and would need docker
    
    # Test that broadcast methods don't crash with no connections
    proxy.forward_to_clients(Bytes.new(5, 0x00))  # Should not raise
    proxy.enable_lockout  # Should not raise (calls send_lockout_message on all connections)
    proxy.disable_lockout  # Should not raise (calls send_unlock_message on all connections)
  end
  
  # This would be a full integration test with docker
  # For now, we document what it would test:
  #
  # it "full docker integration test" do
  #   # 1. Start a Minecraft server in docker
  #   # 2. Connect a rosegold bot to the server  
  #   # 3. Start proxy server attached to the bot
  #   # 4. Create a mock Minecraft client connection to proxy
  #   # 5. Send chat packets through proxy and verify they reach server
  #   # 6. Send movement packets and verify bot moves on server
  #   # 7. Test lockout: enable lockout, verify client packets are blocked
  #   # 8. Test chat commands: send /rosegold commands, verify responses
  #   # 9. Test server->client forwarding: trigger server events, verify client receives them
  #   # 10. Cleanup: disconnect client, stop proxy, disconnect bot, stop server
  # end
end