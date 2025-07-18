# Protocol-Aware Packet System

This document describes the elegant protocol-aware packet system implemented in rosegold.cr that allows seamless support for multiple Minecraft protocol versions.

## Overview

The protocol-aware packet system provides an elegant `Packet[protocol_version]` syntax for accessing protocol-specific packet IDs while maintaining full backward compatibility with existing code.

## Key Features

- **Elegant Syntax**: `LoginStart[767]` returns the packet ID for MC 1.21
- **Multi-Version Support**: Supports MC 1.18 (758), MC 1.21 (767), and MC 1.21.6 (771)  
- **Backward Compatible**: Existing `packet_id` class getters continue to work
- **Automatic Protocol Detection**: Packets automatically use the correct ID based on detected protocol
- **Compile-Time Performance**: Packet ID mappings are resolved at compile time

## Usage Examples

### Basic Protocol-Specific Packet ID Lookup

```crystal
# Get packet IDs for different protocols
puts Rosegold::Serverbound::KeepAlive[758_u32]  # => 15 (0x0F) - MC 1.18  
puts Rosegold::Serverbound::KeepAlive[767_u32]  # => 18 (0x12) - MC 1.21
puts Rosegold::Serverbound::KeepAlive[771_u32]  # => 18 (0x12) - MC 1.21.6

# LoginStart uses same ID across versions
puts Rosegold::Serverbound::LoginStart[758_u32]  # => 0 (0x00) - All versions
```

### Protocol Support Checking

```crystal
# Check if a packet supports a specific protocol
if Rosegold::Serverbound::KeepAlive.supports_protocol?(767_u32)
  puts "KeepAlive supports MC 1.21!"
end

# Get all supported protocols
protocols = Rosegold::Serverbound::KeepAlive.supported_protocols
# => [758, 767, 771]
```

### Automatic Protocol-Aware Packet Creation

```crystal
# Packets automatically use correct ID based on client protocol version
Rosegold::Client.protocol_version = 767_u32

keep_alive = Rosegold::Serverbound::KeepAlive.new(12345_i64)
bytes = keep_alive.write
# Automatically uses packet ID 0x12 for MC 1.21

# When protocol is 758 (MC 1.18), same packet uses ID 0x0F
```

### Backward Compatibility

```crystal
# Existing code continues to work unchanged
puts Rosegold::Serverbound::KeepAlive.packet_id  # Uses first defined protocol's ID

# Registration system remains compatible
# (Uses first protocol's packet ID for registration)
```

## Implementation Details

### Packet Class Definition

```crystal
class Rosegold::Serverbound::KeepAlive < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  
  # Define protocol-specific packet IDs using the packet_ids macro
  packet_ids({
    758_u32 => 0x0F_u8,  # MC 1.18
    767_u32 => 0x12_u8,  # MC 1.21 - CHANGED!
    771_u32 => 0x12_u8   # MC 1.21.6
  })

  # ... rest of packet implementation
  
  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full keep_alive_id
    end.to_slice
  end
end
```

### Generated Methods

The `packet_ids` macro automatically generates:

- `def self.[](protocol_version : UInt32) : UInt8` - Elegant lookup syntax
- `class_getter packet_id : UInt8` - Backward compatibility (uses first protocol's ID)
- `def self.packet_id_for_protocol(protocol_version : UInt32) : UInt8` - Explicit protocol lookup
- `def self.default_packet_id : UInt8` - Default fallback ID
- `def self.supported_protocols : Array(UInt32)` - List of supported protocols
- `def self.supports_protocol?(protocol_version : UInt32) : Bool` - Protocol support check

## Protocol Data

The system includes comprehensive protocol data extracted from Minecraft Wiki:

- **Protocol 758 (MC 1.18)**: [Documentation](https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=3024144)
- **Protocol 767 (MC 1.21)**: [Documentation](https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2789623)  
- **Protocol 771 (MC 1.21.6)**: [Documentation](https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2772783)

### Key Packet ID Changes

| Packet | MC 1.18 (758) | MC 1.21 (767) | MC 1.21.6 (771) |
|--------|----------------|----------------|------------------|
| LoginStart | 0x00 | 0x00 | 0x00 |
| KeepAlive | 0x0F | 0x12 | 0x12 |
| ChatMessage | 0x03 | 0x05 | 0x05 |
| PlayerPosition | 0x11 | 0x14 | 0x14 |
| PlayerLook | 0x13 | 0x16 | 0x16 |

## Testing

The system includes comprehensive tests covering:

- Protocol-specific packet ID lookup via `[]` syntax
- Backward compatibility with existing `packet_id` getters  
- Protocol support checking and validation
- Automatic protocol-aware packet writing
- Error handling for unknown protocols

Run the protocol mapping tests:

```bash
crystal spec spec/packets/protocol_mapping_spec.cr
crystal spec spec/packets/protocol_data_spec.cr
```

## Migration Guide

### For New Packets

```crystal
class Rosegold::Serverbound::YourNewPacket < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  
  packet_ids({
    758_u32 => 0xXX_u8,  # MC 1.18 ID
    767_u32 => 0xYY_u8,  # MC 1.21 ID  
    771_u32 => 0xYY_u8   # MC 1.21.6 ID
  })
  
  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # ... rest of packet data
    end.to_slice
  end
end
```

### For Existing Packets

1. Include `Rosegold::Packets::ProtocolMapping`
2. Replace `class_getter packet_id = 0xXX_u8` with `packet_ids({...})`  
3. Update `write` method to use `self.class.packet_id_for_protocol(protocol_version)`
4. Add protocol-specific packet IDs from protocol documentation

## Performance

- **Compile-Time Resolution**: Packet ID mappings are resolved at compile time
- **Zero Runtime Overhead**: No hash lookups or dynamic dispatch
- **Memory Efficient**: Packet ID constants are stored as compile-time data
- **Registration Compatible**: Uses first protocol's ID for existing registration system

## Future Extensibility

The system is designed for easy extension to new protocol versions:

```crystal
packet_ids({
  758_u32 => 0x0F_u8,  # MC 1.18
  767_u32 => 0x12_u8,  # MC 1.21
  771_u32 => 0x12_u8,  # MC 1.21.6
  777_u32 => 0x15_u8   # Hypothetical MC 1.22
})
```

Simply add new protocol mappings to the `packet_ids` definition and the system automatically supports the new version.