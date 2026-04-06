require "../packet"

class Rosegold::Clientbound::SetTime < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x6A_u32, # MC 1.21.8
    774_u32 => 0x6F_u32, # MC 1.21.11
    775_u32 => 0x71_u32, # MC 26.1
  })

  property world_age : Int64
  property time_of_day : Int64
  property? tick_day_time : Bool

  def initialize(@world_age, @time_of_day, @tick_day_time = true); end

  def self.read(packet)
    world_age = packet.read_long
    if Client.protocol_version >= 775_u32
      # 26.1: world clocks format — Map<WorldClock, ClockState>
      clock_count = packet.read_var_int
      time_of_day = 0_i64
      tick_day_time = true
      clock_count.times do
        clock_id = packet.read_var_int
        total_ticks = packet.read_var_long.to_i64
        _partial_tick = packet.read_float
        rate = packet.read_float
        # Use first clock's total_ticks as time_of_day (typically daytime clock)
        if clock_id == 0
          time_of_day = total_ticks
          tick_day_time = rate > 0.0_f32
        end
      end
    else
      time_of_day = packet.read_long
      tick_day_time = packet.read_bool
    end
    self.new(world_age, time_of_day, tick_day_time)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full world_age
      if Client.protocol_version >= 775_u32
        # 26.1: world clocks format — 1 entry for daytime clock
        buffer.write 1_u32 # clock_count
        buffer.write 0_u32 # clock_id = daytime
        buffer.write time_of_day.to_u64
        buffer.write 0.0_f32                             # partial_tick
        buffer.write(tick_day_time? ? 1.0_f32 : 0.0_f32) # rate
      else
        buffer.write_full time_of_day
        buffer.write tick_day_time?
      end
    end.to_slice
  end

  def callback(client)
    client.dimension.time_of_day = time_of_day
    client.dimension.world_age = world_age
    Log.debug { "SetTime: world_age=#{world_age}, time_of_day=#{time_of_day}, tick_day_time=#{tick_day_time?}" }
  end
end
