require "../packet"

class Rosegold::Clientbound::SetExperience < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x60_u32, # MC 1.21.8
    774_u32 => 0x65_u32, # MC 1.21.11
    775_u32 => 0x67_u32, # MC 26.1
  })

  property \
    experience_progress : Float32,
    experience_level : UInt32,
    total_experience : UInt32

  def initialize(@experience_progress, @experience_level, @total_experience); end

  def self.read(packet)
    self.new(
      packet.read_float,
      packet.read_var_int,
      packet.read_var_int
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write experience_progress
      buffer.write experience_level
      buffer.write total_experience
    end.to_slice
  end

  def callback(client)
    Log.debug { "xp level=#{experience_level} total=#{total_experience} progress=#{experience_progress}" }

    old_experience_level = client.player.experience_level
    old_total_experience = client.player.total_experience
    old_experience_progress = client.player.experience_progress

    client.player.experience_level = experience_level
    client.player.total_experience = total_experience
    client.player.experience_progress = experience_progress

    if experience_level != old_experience_level ||
       total_experience != old_total_experience ||
       experience_progress != old_experience_progress
      client.emit_event Event::ExperienceChanged.new(
        old_experience_level, experience_level,
        old_total_experience, total_experience,
        old_experience_progress, experience_progress
      )
    end
  end
end
