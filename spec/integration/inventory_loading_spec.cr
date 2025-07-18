require "../spec_helper"

Spectator.describe "Inventory loading on connect" do
  it "should receive inventory initialization packets after connecting" do
    test_client = client
    
    # Track inventory-related packets
    window_items_received = false
    cursor_initialized = false
    
    # Log all packets to see what we're getting
    packet_count = 0
    test_client.on Rosegold::Event::RawPacket do |event|
      if packet_count >= 0
        packet_count += 1
        packet_id = event.bytes[0]
        puts "Packet #{packet_count}: 0x#{packet_id.to_s(16)} (#{event.bytes.size} bytes)"
        
        # Stop logging after 50 packets to avoid spam
        if packet_count >= 50
          puts "... (stopped logging after 50 packets)"
          packet_count = -1000  # Skip further logging
        end
      end
    end
    
    # Listen for both old WindowItems and new SetContainerContent packets
    test_client.on Rosegold::Clientbound::WindowItems do |packet|
      if packet.window_id == 0 # Player inventory
        window_items_received = true
        puts "WindowItems (0x14) received for window #{packet.window_id}"
      end
    end
    
    test_client.on Rosegold::Clientbound::SetContainerContent do |packet|
      if packet.window_id == 0 # Player inventory
        window_items_received = true
        puts "SetContainerContent (0x14) received:"
        puts "  window_id = #{packet.window_id}"
        puts "  state_id = #{packet.state_id}"
        puts "  slots.size = #{packet.slots.size}"
        puts "  cursor = #{packet.cursor.inspect}"
        puts "  cursor.empty? = #{packet.cursor.empty?}"
        puts "  Before callback: inventory.cursor = #{test_client.inventory.cursor.inspect rescue "nil"}"
        
        # Give a moment for callback to execute, then check again
        spawn do
          sleep 0.01
          puts "  After callback: inventory.cursor = #{test_client.inventory.cursor.inspect rescue "nil"}"
        end
      end
    end
    
    test_client.on Rosegold::Clientbound::SetSlot do |packet|
      if packet.window_id == -1 && packet.slot.slot_number == -1 # Cursor slot
        cursor_initialized = true
        puts "Cursor initialized via SetSlot: #{packet.slot.inspect}"
      end
    end
    
    # Connect and wait for packets
    test_client.connect
    
    # Wait up to 30 seconds for inventory packets
    timeout = 600 # 30 seconds at 50ms intervals
    while timeout > 0 && (!window_items_received || !cursor_initialized)
      sleep 0.05
      timeout -= 1
      break unless test_client.connected?
    end
    
    puts "Final inventory state:"
    puts "  inventory.ready? = #{test_client.inventory.ready?}"
    puts "  inventory.slots = #{test_client.inventory.slots.inspect}"
    puts "  inventory.cursor = #{test_client.inventory.cursor.inspect}"
    puts "  window_items_received = #{window_items_received}"
    puts "  cursor_initialized = #{cursor_initialized}"
    
    puts "Final check:"
    puts "  window_items_received = #{window_items_received}"
    puts "  test_client.inventory.ready? = #{test_client.inventory.ready?}"
    puts "  test_client.inventory.slots.nil? = #{test_client.inventory.slots.nil?}"
    puts "  test_client.inventory.cursor.nil? = #{test_client.inventory.cursor.nil?}"
    puts "  test_client.inventory.closed? = #{test_client.inventory.closed?}"
    
    expect(window_items_received).to be_true
    expect(test_client.inventory.ready?).to be_true
    
    test_client.connection?.try &.disconnect Rosegold::Chat.new "Test complete"
  end
end