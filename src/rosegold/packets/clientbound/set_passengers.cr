class Rosegold::Clientbound::SetPassengers < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x64_u8, # MC 1.21.8,
  })

  property \
    entity_id : UInt64,
    passengers : Array(UInt64)

  def initialize(@entity_id, @passengers)
  end

  def self.read(packet)
    entity_id = packet.read_var_long
    passenger_count = packet.read_var_long
    passengers = passenger_count.times.map { packet.read_var_long }.to_a

    self.new(entity_id, passengers)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write_var_int(passengers.length)
      passengers.each do |eid|
        buffer.write_var_long(eid)
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received set passengers packet for entity ID #{entity_id}, passengers: #{passengers}" }
    if entity = client.dimension.entities[entity_id]?
      entity.passenger_ids = passengers
      entity.update_passengers client
    else
      Log.warn { "Received set passengers packet for unknown entity ID #{entity_id}" }
    end
  end
end
