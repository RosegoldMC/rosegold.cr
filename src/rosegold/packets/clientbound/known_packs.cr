require "../packet"

class Rosegold::Clientbound::KnownPacks < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for KnownPacks
  packet_ids({
    767_u32 => 0x0E_u8, # MC 1.21
    769_u32 => 0x0E_u8, # MC 1.21.4,
    771_u32 => 0x0E_u8, # MC 1.21.6,
    772_u32 => 0x0E_u8, # MC 1.21.8,
  })

  class_getter state = ProtocolState::CONFIGURATION

  property known_packs : Array(NamedTuple(namespace: String, id: String, version: String))

  def initialize(@known_packs = [] of NamedTuple(namespace: String, id: String, version: String))
  end

  def self.read(packet)
    # Read number of known packs
    pack_count = packet.read_var_int

    # Read each known pack
    known_packs = Array(NamedTuple(namespace: String, id: String, version: String)).new(pack_count) do
      namespace = packet.read_var_string
      id = packet.read_var_string
      version = packet.read_var_string
      {namespace: namespace, id: id, version: version}
    end

    self.new(known_packs)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write known_packs.size
      known_packs.each do |pack|
        buffer.write pack[:namespace]
        buffer.write pack[:id]
        buffer.write pack[:version]
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received known packs from server: #{known_packs.size} packs" }

    # Respond with our known packs (for now, we acknowledge all server packs)
    response = Rosegold::Serverbound::KnownPacks.new(known_packs)
    client.send_packet! response
  end
end
