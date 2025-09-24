require "../packet"

class Rosegold::Clientbound::PlayerInfoRemove < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x3E_u8, # MC 1.21.8,
  })

  property uuids : Array(UUID)

  def initialize(@uuids); end

  def self.read(packet)
    count = packet.read_var_int
    uuids = Array(UUID).new(count.to_i32) { packet.read_uuid }
    self.new(uuids)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write uuids.size
      uuids.each { |uuid| buffer.write uuid }
    end.to_slice
  end

  def callback(client)
    Log.debug { "Removing #{uuids.size} players from player list" }
    uuids.each do |uuid|
      if removed_player = client.player_list.delete(uuid)
        Log.debug { "  Removed player: #{removed_player.name} (#{uuid})" }
      end
    end
  end
end
