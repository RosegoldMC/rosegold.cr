require "../serverbound/player_digging"

class Rosegold::Clientbound::AcknowledgePlayerDigging < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x08_u8

  alias Status = Rosegold::Serverbound::PlayerDigging::Status

  property \
    location : Vec3i,
    block_id : UInt16,
    status : Status
  property? \
    successful : Bool

  def initialize(@location, @block_id, @status, @successful)
  end

  def self.read(packet)
    self.new(
      packet.read_bit_location,
      packet.read_var_int.to_u16,
      Status.new(packet.read_var_int.to_i32),
      packet.read_bool
    )
  end

  def callback(client)
    if status == Status::Finish
      client.dimension.set_block_state location, block_id
    end
  end
end
