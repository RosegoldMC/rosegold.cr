class Rosegold::Clientbound::SetSlot < Rosegold::Clientbound::Packet
  packet_id 0x16

  property \
    window_id : UInt8,
    state_id : UInt32,
    slot : UInt16,
    slot_data : Rosegold::Slot

  def initialize(@window_id, @state_id, @slot, @slot_data)
  end

  def self.read(packet)
    new \
      packet.read_byte.to_u8,
      packet.read_var_int,
      packet.read_short.to_u16,
      Rosegold::Slot.read(packet)
  end

  def callback(client)
    if window_id == 0
      Log.debug { "Received set slot for player inventory: #{slot_data}" }
      client.current_window.slots[slot] = slot_data
    elsif client.current_window.nil? || client.current_window.try &.id != window_id
      Log.warn { "Received set slot for an unknown or mismatched window. Ignoring." }
      return
    else
      Log.debug { "Received set slot for window #{window_id}, slot #{slot}." }

      client.current_window.try do |window|
        window.slots[slot] = slot_data
      end
    end
  end
end
