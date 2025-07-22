class Rosegold::Clientbound::EntityPosition < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x28_u8, # MC 1.18
    767_u32 => 0x2F_u8, # MC 1.21
    769_u32 => 0x2F_u8, # MC 1.21.4,
    771_u32 => 0x28_u8, # MC 1.21.6,
  })

  property \
    entity_id : UInt64,
    delta_x : Int16,
    delta_y : Int16,
    delta_z : Int16

  property? \
    on_ground : Bool

  def initialize(@entity_id, @delta_x, @delta_y, @delta_z, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_long
    delta_x = packet.read_short
    delta_y = packet.read_short
    delta_z = packet.read_short
    on_ground = packet.read_bool

    self.new(entity_id, delta_x, delta_y, delta_z, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write delta_x
      buffer.write delta_y
      buffer.write delta_z
      buffer.write on_ground
    end.to_slice
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity position packet for unknown entity ID #{entity_id}" }
      return
    end

    new_pos = entity.position.plus(delta_x / 128.0 / 32.0, delta_y / 128.0 / 32.0, delta_z / 128.0 / 32.0)

    entity.position = new_pos
  end
end
