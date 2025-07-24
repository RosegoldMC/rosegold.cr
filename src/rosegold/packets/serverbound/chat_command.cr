require "../packet"

class Rosegold::Serverbound::ChatCommand < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x06_u8, # MC 1.21.8,
  })

  property command : String

  def initialize(@command : String)
    @command = @command.lchop('/')
  end

  def self.read(io)
    command = io.read_var_string
    self.new(command)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write command
    end.to_slice
  end
end
