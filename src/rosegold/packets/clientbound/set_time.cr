require "../packet"

class Rosegold::Clientbound::SetTime < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x6A_u32, # MC 1.21.8
    774_u32 => 0x6F_u32, # MC 1.21.11
  })

  property world_age : Int64
  property time_of_day : Int64
  property tick_day_time : Bool

  def initialize(@world_age, @time_of_day, @tick_day_time = true); end

  def self.read(packet)
    world_age = packet.read_long
    time_of_day = packet.read_long
    tick_day_time = packet.read_bool
    self.new(world_age, time_of_day, tick_day_time)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full world_age
      buffer.write_full time_of_day
      buffer.write tick_day_time
    end.to_slice
  end

  def callback(client)
    Log.debug { "SetTime: world_age=#{world_age}, time_of_day=#{time_of_day}, tick_day_time=#{tick_day_time}" }
  end
end
