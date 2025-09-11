class Rosegold::Clientbound::WindowItems < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x14_u8, # MC 1.18
  })

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
    slots = Array(WindowSlot).new(num_slots) do |slot_number|
      WindowSlot.new(slot_number, Slot.read(packet))
    end

    cursor = WindowSlot.new -1, Slot.read(packet)

    self.new(window_id, state_id, slots, cursor)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
      buffer.write state_id
      buffer.write slots.size
      slots.each &.write buffer
      buffer.write cursor
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received #{slots.size} window items for window #{window_id} state #{state_id}" }
    if window_id == 0
      slot_array = slots.map(&.as(Rosegold::Slot))
      client.inventory_menu.update_all_slots(slot_array, cursor.as(Rosegold::Slot), state_id)
    elsif client.container_menu && client.container_menu.id == window_id
      slot_array = slots.map(&.as(Rosegold::Slot))
      client.container_menu.update_all_slots(slot_array, cursor.as(Rosegold::Slot), state_id)
    else
      Log.debug { "Received window items for an unknown or mismatched window. Ignoring." }
      Log.debug { self }
    end
  end
end
