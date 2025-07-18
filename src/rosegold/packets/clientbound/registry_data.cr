require "../packet"

class Rosegold::Clientbound::RegistryData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for RegistryData
  packet_ids({
    767_u32 => 0x05_u8, # MC 1.21
    771_u32 => 0x05_u8, # MC 1.21.6
  })

  class_getter state = ProtocolState::CONFIGURATION

  property \
    registry_id : String,
    entries : Array(NamedTuple(id: String, data: Bytes?))

  def initialize(@registry_id, @entries = [] of NamedTuple(id: String, data: Bytes?))
  end

  def self.read(packet)
    registry_id = packet.read_var_string
    
    # Read entries array
    entry_count = packet.read_var_int
    entries = Array(NamedTuple(id: String, data: Bytes?)).new(entry_count) do
      entry_id = packet.read_var_string
      has_data = packet.read_bool
      data = has_data ? packet.read_var_bytes : nil
      {id: entry_id, data: data}
    end

    self.new(registry_id, entries)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write registry_id
      buffer.write entries.size
      entries.each do |entry|
        buffer.write entry[:id]
        if data = entry[:data]
          buffer.write true
          buffer.write data
        else
          buffer.write false
        end
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received registry data for #{registry_id} with #{entries.size} entries" }
  end
end