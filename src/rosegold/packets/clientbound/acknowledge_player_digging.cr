class Rosegold::Clientbound::AcknowledgePlayerDigging < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x08_u8
  property \
    location : Tuple(Int32, Int32, Int32),
    block : UInt32,
    status : UInt32
  property? \
    successful : Bool

  def initialize(@location, @block, @status, @successful)
  end

  def self.read(packet)
    self.new(
      packet.read_bit_position,
      packet.read_var_int,
      packet.read_var_int,
      packet.read_bool
    )
  end

  def callback(client)
    return unless status == 0

    spawn do
      sleep 2
      Log.debug { "AcknowledgePlayerDigging: #{location}" }
      client.queue_packet Rosegold::Serverbound::PlayerDigging.new \
        status: 2_u32,
        location: location_vec,
        face: 1_u32
    end
  end

  def location_vec
    Vec3d.new location[0], location[1], location[2]
  end
end
