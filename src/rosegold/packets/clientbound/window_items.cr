class Rosegold::Clientbound::WindowItems < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x14_u8

  property \
    window_id : UInt8,
    state_id : UInt32,
    slots : Array(WindowSlot),
    cursor : WindowSlot

  def initialize(@window_id, @state_id, @slots, @cursor)
  end

  def self.read(packet)
    window_id = packet.read_byte.to_u8
    state_id = packet.read_var_int

    num_slots = packet.read_var_int
    slots = Array(WindowSlot).new(num_slots) do |slot_nr|
      WindowSlot.new(slot_nr, Slot.read(packet))
    end

    cursor = WindowSlot.new -1, Slot.read(packet)

    self.new(window_id, state_id, slots, cursor)
  end

  def callback(client)
    if window_id == 0
      client.inventory.state_id = state_id
      client.inventory.slots = slots
      client.inventory.cursor = cursor
    elsif client.window.id == window_id
      client.window.state_id = state_id
      client.window.slots = slots
      client.window.cursor = cursor
    else
      Log.warn { "Received window items for an unknown or mismatched window. Ignoring." }
      Log.trace { self }
    end
  end
end
