require "../packet"

class Rosegold::Clientbound::UpdateHealth < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x61_u8, # MC 1.21.8,
  })

  property \
    health : Float32,
    food : UInt32,
    saturation : Float32

  def initialize(@health, @food, @saturation); end

  def self.read(packet)
    self.new(
      packet.read_float,
      packet.read_var_int,
      packet.read_float
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write health
      buffer.write food
      buffer.write saturation
    end.to_slice
  end

  def callback(client)
    Log.debug { "health=#{health/2}❤ food=#{food*5}% saturation=#{saturation}" }

    client.player.health = health
    client.player.food = food
    client.player.saturation = saturation

    # auto-respawn for now. we could also stay dead if user wishes it
    if health <= 0
      client.queue_packet Serverbound::ClientStatus.new :respawn
    end
  end
end
