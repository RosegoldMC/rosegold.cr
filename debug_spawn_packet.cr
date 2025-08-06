#!/usr/bin/env crystal

require "./src/minecraft/io.cr"
require "./src/rosegold/packets/clientbound/spawn_living_entity.cr"
require "./src/rosegold/client.cr"

# Set protocol version
Rosegold::Client.protocol_version = 772_u32

# Create a minimal spawn packet
packet = Rosegold::Clientbound::SpawnLivingEntity.new(
  entity_id: 1_u32,
  uuid: UUID.new("00000000-0000-0000-0000-000000000000"),
  entity_type: 1_u32,
  x: 0.0,
  y: 0.0, 
  z: 0.0,
  pitch: 0.0_f32,
  yaw: 0.0_f32,
  head_yaw: 0.0_f32,
  data: 0_u32,
  velocity_x: 0_i16,
  velocity_y: 0_i16,
  velocity_z: 0_i16
)

# Write the packet and check byte count
bytes = packet.write
puts "Total packet bytes: #{bytes.size}"
puts "Packet bytes (hex): #{bytes.hexstring}"

# Expected size breakdown:
# - Packet ID (VarInt): 1 byte (0x01)
# - Entity ID (VarInt): 1 byte (0x01)  
# - UUID: 16 bytes
# - Entity Type (VarInt): 1 byte (0x01)
# - X (Double): 8 bytes
# - Y (Double): 8 bytes  
# - Z (Double): 8 bytes
# - Pitch (Angle): 1 byte
# - Yaw (Angle): 1 byte
# - Head Yaw (Angle): 1 byte
# - Data (VarInt): 1 byte (0x00)
# - Velocity X (Short): 2 bytes
# - Velocity Y (Short): 2 bytes
# - Velocity Z (Short): 2 bytes
# Total expected: 1+1+16+1+8+8+8+1+1+1+1+2+2+2 = 53 bytes

puts "Expected size: 53 bytes"
puts "Difference: #{bytes.size - 53} bytes"