require "../packet"

# Plugin Message (serverbound) packet
# Used for sending data on plugin channels
# The minecraft:brand channel is used to identify the client brand
class Rosegold::Serverbound::PluginMessage < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x17_u8, # MC 1.21.8
  })

  property channel : String
  property data : Bytes

  def initialize(@channel : String, @data : Bytes)
  end

  # Convenience constructor for string data
  def self.new(channel : String, data : String)
    data_bytes = data.to_slice
    new(channel, data_bytes)
  end

  # Convenience constructor for minecraft:brand channel
  def self.brand(brand_name : String)
    new("minecraft:brand", brand_name)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write channel
      buffer.write data
    end.to_slice
  end
end
