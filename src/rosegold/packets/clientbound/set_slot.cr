class Rosegold::Clientbound::SetSlot < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x16_u8

  property \
    window_id : Int8,
    state_id : UInt32,
    slot_nr : Int16,
    slot_data : Rosegold::Slot

  def initialize(@window_id, @state_id, @slot_nr, @slot_data)
  end

  def self.read(packet)
    new \
      packet.read_byte.to_i8!,
      packet.read_var_int,
      packet.read_short.to_i16,
      Rosegold::Slot.read(packet)
  end

  def callback(client)
    if window_id == -1 && slot_nr == -1
      client.window.cursor = slot_data
    elsif window_id == 0
      client.inventory.slots[slot_nr] = slot_data
    elsif client.window.id == window_id
      client.window.slots[slot_nr] = slot_data
    else
      Log.warn { "Received slot update for an unknown or mismatched window. Ignoring." }
      Log.trace { self }
    end
  end
end
