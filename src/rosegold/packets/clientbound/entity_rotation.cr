class Rosegold::Clientbound::EntityRotation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x2B_u8, # MC 1.18
    767_u32 => 0x2B_u8, # MC 1.21
    771_u32 => 0x2B_u8, # MC 1.21.6
  })

  property \
    entity_id : UInt64,
    yaw : Float32,
    pitch : Float32

  property? \
    on_ground : Bool

  def initialize(@entity_id, @yaw, @pitch, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_long
    yaw = packet.read_angle256_deg
    pitch = packet.read_angle256_deg
    on_ground = packet.read_bool

    self.new(entity_id, yaw, pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write yaw
      buffer.write pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity rotation packet for entity ID #{entity_id}, yaw #{yaw}, pitch #{pitch}" }
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity rotation packet for unknown entity ID #{entity_id}" }
      return
    end

    entity.yaw = yaw
    entity.pitch = pitch
    entity.on_ground = on_ground?
  end
end
