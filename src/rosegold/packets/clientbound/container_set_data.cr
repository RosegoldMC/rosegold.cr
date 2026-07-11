class Rosegold::Clientbound::ContainerSetData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x13_u32, # MC 1.21.8
    773_u32 => 0x13_u32, # MC 1.21.9
    774_u32 => 0x13_u32, # MC 1.21.11
    775_u32 => 0x13_u32, # MC 26.1
    776_u32 => 0x13_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  property \
    container_id : UInt32,
    property_id : Int16,
    value : Int16

  def initialize(@container_id, @property_id, @value)
  end

  def self.read(packet)
    container_id = packet.read_var_int
    property_id = packet.read_short
    value = packet.read_short
    new container_id, property_id, value
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write container_id
      buffer.write_full property_id
      buffer.write_full value
    end.to_slice
  end

  def callback(client)
    if client.container_menu.id == container_id
      client.container_menu.properties[property_id] = value
    else
      Log.debug { "Received container property update for unknown or mismatched window. Ignoring. Packet container_id=#{container_id}, client container_id=#{client.container_menu.id}, property=#{property_id}, value=#{value}" }
    end
  end
end
