class Rosegold::Clientbound::SetCooldown < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x16_u32, # MC 1.21.8
    773_u32 => 0x16_u32, # MC 1.21.9
    774_u32 => 0x16_u32, # MC 1.21.11
    775_u32 => 0x16_u32, # MC 26.1
    776_u32 => 0x16_u32, # MC 26.2
    777_u32 => 0x16_u32, # MC 26.3
  })
  class_getter state = ProtocolState::PLAY

  getter group : String
  getter duration : Int32

  def initialize(@group, @duration)
  end

  def self.read(packet)
    size = packet.read_var_int
    raise IO::Error.new("Cooldown group exceeds 32767 bytes") if size > 32_767
    raise IO::EOFError.new if size > packet.size - packet.pos

    group = packet.read_var_string(size)
    raise IO::Error.new("Invalid UTF-8 in cooldown group") unless group.valid_encoding?

    duration = packet.read_var_int.to_i32!
    new group, duration
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write group
      buffer.write duration
    end.to_slice
  end

  def callback(client)
    client.record_item_cooldown(group, duration)
  end
end
