class Rosegold::Clientbound::SetSlot < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x14_u8, # MC 1.21.8,
  })

  property \
    window_id : Int8,
    state_id : UInt32,
    slot : WindowSlot

  def initialize(@window_id, @state_id, @slot)
  end

  def self.read(packet)
    new \
      packet.read_byte.to_i8!,
      packet.read_var_int,
      WindowSlot.new \
        packet.read_short.to_i16,
        Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
      buffer.write state_id
      buffer.write_full slot.slot_number.to_i16
      buffer.write slot
    end.to_slice
  end

  def callback(client)
    if window_id == -1 && slot.slot_number == -1
      client.container_menu.cursor = slot.as(Rosegold::Slot)
    elsif window_id == 0
      client.inventory_menu.update_slot(slot.slot_number, slot.as(Rosegold::Slot), state_id)
    elsif client.container_menu && client.container_menu.id == window_id
      client.container_menu.update_slot(slot.slot_number, slot.as(Rosegold::Slot), state_id)
    else
      container_id = client.container_menu.try(&.id) || "nil"
      Log.debug { "Received slot update for an unknown or mismatched window. Ignoring. Packet window_id=#{window_id}, client container_id=#{container_id}, slot=#{slot}" }
      Log.debug { self }
    end
  end
end
