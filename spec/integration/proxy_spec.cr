require "../spec_helper"

Spectator.describe "Proxy Integration" do
  it "can create proxy server" do
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25566)
    expect(proxy.host).to eq("127.0.0.1")
    expect(proxy.port).to eq(25566)
  end

  it "can create bot client" do
    # Create a bot client (we'll use offline mode for testing)
    offline_uuid = UUID.random.to_s
    offline_username = "TestBot"
    bot = Rosegold::Client.new(
      "localhost", 25565, 
      {uuid: offline_uuid, username: offline_username}
    )
    
    expect(bot.host).to eq("localhost")
    expect(bot.port).to eq(25565)
  end

  it "can handle lockout state changes" do
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25568)
    
    # Initially lockout should be disabled
    expect(proxy.lockout_active?).to be_false
    
    # Enable lockout
    proxy.enable_lockout
    expect(proxy.lockout_active?).to be_true
    
    # Disable lockout
    proxy.disable_lockout
    expect(proxy.lockout_active?).to be_false
  end

  # This would be a more comprehensive test that would require a running server
  # For now, we'll comment it out and focus on unit tests
  # 
  # it "can forward packets between client and bot" do
  #   # This test would require:
  #   # 1. A running Minecraft server (via docker)
  #   # 2. A rosegold bot connected to that server
  #   # 3. A proxy server attached to the bot
  #   # 4. A mock Minecraft client connected to the proxy
  #   # 5. Verification that packets flow correctly
  # end

  it "can intercept chat commands" do
    proxy = Rosegold::ProxyServer.new("127.0.0.1", 25569)
    
    # Create a mock connection for testing
    # We'll need to implement this more fully for real testing
    # For now, just verify the command parsing logic
    
    # Test /rosegold help command interception
    expect(proxy.intercept_chat("/rosegold help", nil)).to be_true
    
    # Test regular chat should not be intercepted
    expect(proxy.intercept_chat("Hello world", nil)).to be_false
    
    # Test /rosegold status command interception  
    expect(proxy.intercept_chat("/rosegold status", nil)).to be_true
  end
end