require "../packet"

class Rosegold::Clientbound::UpdateTags < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for UpdateTags
  packet_ids({
    767_u32 => 0x08_u8, # MC 1.21
    771_u32 => 0x08_u8, # MC 1.21.6
  })

  class_getter state = ProtocolState::CONFIGURATION

  alias TagType = NamedTuple(type: String, tags: Array(NamedTuple(name: String, entries: Array(UInt32))))

  property tag_types : Array(TagType)

  def initialize(@tag_types = [] of TagType)
  end

  def self.read(packet)
    # Read tag types array
    type_count = packet.read_var_int
    tag_types = Array(TagType).new(type_count) do
      type_name = packet.read_var_string
      
      # Read tags for this type
      tag_count = packet.read_var_int
      tags = Array(NamedTuple(name: String, entries: Array(UInt32))).new(tag_count) do
        tag_name = packet.read_var_string
        
        # Read entries for this tag
        entry_count = packet.read_var_int
        entries = Array(UInt32).new(entry_count) do
          packet.read_var_int
        end
        
        {name: tag_name, entries: entries}
      end
      
      {type: type_name, tags: tags}
    end

    self.new(tag_types)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write tag_types.size
      tag_types.each do |tag_type|
        buffer.write tag_type[:type]
        buffer.write tag_type[:tags].size
        tag_type[:tags].each do |tag|
          buffer.write tag[:name]
          buffer.write tag[:entries].size
          tag[:entries].each do |entry|
            buffer.write entry
          end
        end
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received tag updates for #{tag_types.size} tag types" }
  end
end