require "../packet"

class Rosegold::Clientbound::TimeUpdate < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x59_u8

  property \
    world_age : Int64,
    region_age : Int64

  def initialize(@world_age, @region_age); end

  def self.read(packet)
    self.new(
      packet.read_long,
      packet.read_long
    )
  end

  def callback(client)
    client.player.time.set region_age

    age = world_age
    time = Time.local.to_unix_ms

    if client.world_age == 0
      client.last_time = time
      client.world_age = age
      return
    end

    diff_age = age - client.world_age
    diff_time = time - client.last_time

    client.world_age = age
    client.last_time = time

    tps = diff_age / (diff_time / 1000)
    client.tps = ((tps * 100).round / 100).clamp(0_f64, 20_f64)
  end
end
