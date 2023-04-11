class Rosegold::Clientbound::WindowItems < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x14_u8

  property \
    window_id : UInt8,
    state_id : UInt32,
    slots : Array(Slot),
    cursor : Slot

  def initialize(@window_id, @state_id, @slots, @cursor)
  end

  def self.read(packet)
    window_id = packet.read_byte.to_u8
    state_id = packet.read_var_int

    slots = Array(Slot).new(packet.read_var_int) do
      Slot.read(packet)
    end

    cursor = Slot.read(packet)

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
