require "../serverbound/player_digging"

# Some servers do not send this.
class Rosegold::Clientbound::AcknowledgePlayerDigging < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x08_u8, # MC 1.18
  })

  alias Status = Rosegold::Serverbound::PlayerDigging::Status

  property \
    location : Vec3i,
    block_id : UInt16,
    status : Status,
    sequence : Int32
  property? \
    successful : Bool

  def initialize(@location, @block_id, @status, @successful, @sequence = 0)
  end

  def self.read(packet)
    location = packet.read_bit_location
    block_id = packet.read_var_int.to_u16
    status = Status.new(packet.read_var_int.to_i32)
    successful = packet.read_bool

    # MC 1.21+ includes sequence number
    sequence = if Client.protocol_version >= 767_u32
                 packet.read_var_int.to_i32
               else
                 0
               end

    self.new(location, block_id, status, successful, sequence)
  end

  def callback(client)
    Log.debug { "dig ack #{self}" }

    # Remove pending operation if sequence number is provided (MC 1.21+)
    if sequence > 0 && client.protocol_version >= 767_u32
      client.pending_block_operations.delete(sequence)
    end

    if status == Status::Finish && successful?
      client.dimension.set_block_state location, block_id
    end
  end
end
