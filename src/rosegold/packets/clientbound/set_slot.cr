class Rosegold::Clientbound::SetSlot < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x16_u8

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
      buffer.write @@packet_id
      buffer.write window_id
      buffer.write state_id
      buffer.write_full slot.slot_nr.to_i16
      buffer.write slot
    end.to_slice
  end

  def callback(client)
    Log.debug { "Server set slot #{slot}" }
    if window_id == -1 && slot.slot_nr == -1
      client.window.cursor = slot
    elsif window_id == 0
      client.inventory.slots[slot.slot_nr] = slot
    elsif client.window.id == window_id
      client.window.slots[slot.slot_nr] = slot
    else
      Log.warn { "Received slot update for an unknown or mismatched window. Ignoring." }
      Log.debug { self }
    end
  end
end
