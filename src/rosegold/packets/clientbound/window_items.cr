class Rosegold::Clientbound::WindowItems < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x14_u8

  property \
    window_id : UInt8,
    state_id : UInt32,
    count : UInt32,
    slot_data : Array(Rosegold::Slot),
    carried_item : Rosegold::Slot

  def initialize(@window_id, @state_id, @count, @slot_data, @carried_item)
  end

  def self.read(packet)
    window_id = packet.read_byte.to_u8
    state_id = packet.read_var_int

    count = packet.read_var_int
    slot_data = Array(Rosegold::Slot).new(count)

    count.times do
      slot_data << Rosegold::Slot.read(packet)
    end

    carried_item = Rosegold::Slot.read(packet)

    self.new(window_id, state_id, count, slot_data, carried_item)
  end

  def callback(client)
    if window_id == 0
      Log.debug { "Received window items for player inventory: #{slot_data}" }
      client.current_window.slots = slot_data
    elsif client.current_window.nil? || client.current_window.try &.id != window_id
      Log.warn { "Received window items for an unknown or mismatched window. Ignoring." }
      return
    else
      Log.debug { "Received window items for window #{window_id}." }

      client.current_window.slots = slot_data
    end
  end
end
