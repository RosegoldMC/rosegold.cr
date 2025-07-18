# Protocol-Aware Packet System Example
# Demonstrates the elegant Packet[protocol_version] syntax

# This example shows how the new system works across different protocol versions
module Rosegold::Packets::Examples
  # Example 1: Elegant protocol-specific packet ID lookup
  def self.demonstrate_packet_lookup
    puts "=== Protocol-Aware Packet ID Lookup ==="

    # LoginStart packet (same ID across versions)
    puts "LoginStart packet IDs:"
    puts "  MC 1.18 (758): 0x#{Rosegold::Serverbound::LoginStart[758_u32].to_s(16).upcase}"
    puts "  MC 1.21 (767): 0x#{Rosegold::Serverbound::LoginStart[767_u32].to_s(16).upcase}"
    puts "  MC 1.21.6 (771): 0x#{Rosegold::Serverbound::LoginStart[771_u32].to_s(16).upcase}"

    puts

    # KeepAlive packet (different IDs between versions)
    puts "KeepAlive packet IDs:"
    puts "  MC 1.18 (758): 0x#{Rosegold::Serverbound::KeepAlive[758_u32].to_s(16).upcase}"
    puts "  MC 1.21 (767): 0x#{Rosegold::Serverbound::KeepAlive[767_u32].to_s(16).upcase}"
    puts "  MC 1.21.6 (771): 0x#{Rosegold::Serverbound::KeepAlive[771_u32].to_s(16).upcase}"

    puts

    # ChatMessage packet (different IDs between versions)
    puts "ChatMessage packet IDs:"
    puts "  MC 1.18 (758): 0x#{Rosegold::Serverbound::ChatMessage[758_u32].to_s(16).upcase}"
    puts "  MC 1.21 (767): 0x#{Rosegold::Serverbound::ChatMessage[767_u32].to_s(16).upcase}"
    puts "  MC 1.21.6 (771): 0x#{Rosegold::Serverbound::ChatMessage[771_u32].to_s(16).upcase}"
  end

  # Example 2: Protocol support checking
  def self.demonstrate_protocol_support
    puts "=== Protocol Support Checking ==="

    protocols = [758_u32, 767_u32, 771_u32, 999_u32]

    protocols.each do |protocol|
      supported = Rosegold::Serverbound::KeepAlive.supports_protocol?(protocol)
      status = supported ? "✓ Supported" : "✗ Not supported"
      puts "  Protocol #{protocol}: #{status}"
    end
  end

  # Example 3: Dynamic packet creation based on protocol
  def self.create_protocol_aware_packets
    puts "=== Dynamic Protocol-Aware Packet Creation ==="

    protocols = [758_u32, 767_u32, 771_u32]

    protocols.each do |protocol|
      # Mock the protocol version
      original_version = Rosegold::Client.protocol_version
      Rosegold::Client.protocol_version = protocol

      begin
        # Create a KeepAlive packet
        keep_alive = Rosegold::Serverbound::KeepAlive.new(12345_i64)
        bytes = keep_alive.write
        packet_id = bytes[0]

        puts "  Protocol #{protocol}: KeepAlive packet uses ID 0x#{packet_id.to_s(16).upcase}"
      ensure
        Rosegold::Client.protocol_version = original_version
      end
    end
  end

  # Example 4: Backward compatibility demonstration
  def self.demonstrate_backward_compatibility
    puts "=== Backward Compatibility ==="

    # The class_getter packet_id still works for registration
    puts "  LoginStart.packet_id: 0x#{Rosegold::Serverbound::LoginStart.packet_id.to_s(16).upcase}"
    puts "  KeepAlive.packet_id: 0x#{Rosegold::Serverbound::KeepAlive.packet_id.to_s(16).upcase}"
    puts "  ChatMessage.packet_id: 0x#{Rosegold::Serverbound::ChatMessage.packet_id.to_s(16).upcase}"

    puts "  (These use the first defined protocol's packet ID for compatibility)"
  end

  # Main demonstration method
  def self.run_all_examples
    demonstrate_packet_lookup
    puts
    demonstrate_protocol_support
    puts
    create_protocol_aware_packets
    puts
    demonstrate_backward_compatibility
  end
end

# Uncomment to run examples:
# Rosegold::Packets::Examples.run_all_examples
