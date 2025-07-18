# Protocol-aware packet ID mapping system
# Provides elegant Packet[protocol_version] syntax for multi-version support

module Rosegold::Packets::ProtocolMapping
  # Macro to define protocol-specific packet IDs for a packet class
  # Usage: packet_ids({758 => 0x00_u8, 767 => 0x01_u8, 771 => 0x01_u8})
  macro packet_ids(mappings)
    # Store the protocol mappings as a constant
    PROTOCOL_PACKET_IDS = {{mappings}}
    
    # Generate the [](protocol_version) method for elegant access
    def self.[](protocol_version : UInt32) : UInt8
      PROTOCOL_PACKET_IDS[protocol_version]? || default_packet_id
    end
    
    # Provide backward compatibility with existing packet_id class getter
    # Use the first protocol's packet ID for registration compatibility
    class_getter packet_id : UInt8 = {{mappings.values.first}}
    
    # Get packet ID for specific protocol version  
    def self.packet_id_for_protocol(protocol_version : UInt32) : UInt8
      self[protocol_version]
    end
    
    # Define default packet ID (typically the latest/most common version)
    def self.default_packet_id : UInt8
      # Use the first defined packet ID as default
      {% first_id = mappings.values.first %}
      {{first_id}}
    end
    
    # Helper method to get all supported protocols
    def self.supported_protocols : Array(UInt32)
      {{mappings.keys}}
    end
    
    # Helper method to check if a protocol is supported
    def self.supports_protocol?(protocol_version : UInt32) : Bool
      PROTOCOL_PACKET_IDS.has_key?(protocol_version)
    end
  end
end
