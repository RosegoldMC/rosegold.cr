class Rosegold::Clientbound::SetSlot < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x14_u32, # MC 1.21.8
    774_u32 => 0x14_u32, # MC 1.21.11
    775_u32 => 0x14_u32, # MC 26.1
  })

  property \
    window_id : Int8,
    state_id : UInt32,
    slot : WindowSlot

  def initialize(@window_id, @state_id, @slot)
  end

  def self.read(packet)
    window_id = packet.read_var_int.to_i8!
    state_id = packet.read_var_int
    slot_number = packet.read_short.to_i16
    slot = Slot.read(packet)
    new window_id, state_id, WindowSlot.new(slot_number, slot)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id.to_i32
      buffer.write state_id
      buffer.write_full slot.slot_number.to_i16
      buffer.write slot
    end.to_slice
  end

  def callback(client)
    # Pre-1.21.5 used window_id=-1, slot_number=-1 to sync the carried item; on
    # 1.21.5+ that role is filled by SetCursorItem. Vanilla still allows -1/-1
    # against legacy stacks, so route it to the cursor for safety.
    if window_id == -1 && slot.slot_number == -1
      menu = client.container_menu
      menu.update_slot(-1, slot.as(Rosegold::Slot), menu.state_id)
    elsif window_id == 0
      client.inventory_menu.update_slot(slot.slot_number, slot.as(Rosegold::Slot), state_id)
    elsif client.container_menu.id == window_id
      client.container_menu.update_slot(slot.slot_number, slot.as(Rosegold::Slot), state_id)
    else
      container_id = client.container_menu.id
      Log.debug { "Received slot update for an unknown or mismatched window. Ignoring. Packet window_id=#{window_id}, client container_id=#{container_id}, slot=#{slot}" }
      Log.debug { self }
    end
  end
end
