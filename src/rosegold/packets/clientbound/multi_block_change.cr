require "../packet"

class Rosegold::Clientbound::MultiBlockChange < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x3f_u8

  property \
    section_x : Int32,
    section_y : Int32,
    section_z : Int32,
    block_states : Array(Tuple(Int32, Int32, Int32, UInt16))

  def initialize(@section_x, @section_y, @section_z, @block_states); end

  def self.read(packet)
    section_pos_bits = packet.read_long
    # here ordered LSB to MSB; use arithmetic shift to preserve sign
    section_y = (section_pos_bits << 44 >> 44).to_i32 # 20 bits
    section_z = (section_pos_bits << 22 >> 42).to_i32 # 22 bits
    section_x = (section_pos_bits >> 42).to_i32       # 22 bits

    packet.read_bool # ignored

    block_states = Array(Tuple(Int32, Int32, Int32, UInt16)).new packet.read_var_int do
      long = packet.read_var_long
      y = section_y * 16 + (long & 0xf).to_u8
      z = section_z * 16 + ((long >> 4) & 0xf).to_u8
      x = section_x * 16 + ((long >> 8) & 0xf).to_u8
      block_state = (long >> 12).to_u16
      {x, y, z, block_state}
    end

    self.new(
      section_x,
      section_y,
      section_z,
      block_states
    )
  end

  def callback(client)
    block_states.each do |x, y, z, block_state|
      Log.debug { "multi block change at #{x}, #{y}, #{z} state: #{block_state}" }
      client.dimension.set_block_state x, y, z, block_state
    end
  end
end
