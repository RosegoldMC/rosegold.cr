require "../packet"

class Rosegold::Clientbound::RegistryData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x07_u8, # MC 1.21.8,
  })

  class_getter state = ProtocolState::CONFIGURATION

  # Type alias for registry entries
  alias RegistryEntry = NamedTuple(id: String, data: Slice(UInt8) | Nil)

  property \
    registry_id : String,
    entries : Array(RegistryEntry)

  def initialize(@registry_id : String, @entries : Array(RegistryEntry) = [] of RegistryEntry)
  end

  def self.read(packet)
    registry_id = packet.read_var_string
    Log.warn { "registry_id => #{registry_id}" }

    # Read entries array
    entry_count = packet.read_var_int
    entries = Array(RegistryEntry).new(entry_count) do
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
    client.registries[registry_id] = self
    Log.trace { "Stored registry #{registry_id} in client registries" }
  end
end
