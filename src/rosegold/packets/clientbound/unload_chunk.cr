require "../packet"

class Rosegold::Clientbound::UnloadChunk < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x21_u8, # MC 1.21.8,
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    # MC 1.21+ format: Position value
    pos = packet.read_bit_location
    chunk_x = pos.x >> 4
    chunk_z = pos.z >> 4
    self.new(chunk_x, chunk_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ format: Position value
      # Convert chunk coordinates to world coordinates (chunk coords * 16)
      world_x = chunk_x << 4
      world_z = chunk_z << 4
      world_y = 0 # Y doesn't matter for chunk unloading

      # Encode position as bit location (inverse of read_bit_location)
      # Format: x (26 bits), z (26 bits), y (12 bits) from MSB to LSB
      value = (world_x.to_i64 & 0x3FFFFFF) << 38 | # x: 26 bits at position 38
              (world_z.to_i64 & 0x3FFFFFF) << 12 | # z: 26 bits at position 12
              (world_y.to_i64 & 0xFFF)             # y: 12 bits at position 0

      buffer.write_full(value)
    end.to_slice
  end

  def callback(client)
    client.dimension.unload_chunk({chunk_x, chunk_z})
  end
end
