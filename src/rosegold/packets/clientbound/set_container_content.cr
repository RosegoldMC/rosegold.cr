# MC 1.21+ replacement for WindowItems packet
class Rosegold::Clientbound::SetContainerContent < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x12_u32, # MC 1.21.8
    774_u32 => 0x12_u32, # MC 1.21.11
  })

  property \
    window_id : UInt32,
    state_id : UInt32,
    slots : Array(WindowSlot),
    cursor : WindowSlot

  def initialize(@window_id, @state_id, @slots, @cursor)
  end

  def self.read(packet)
    window_id = packet.read_var_int
    state_id = packet.read_var_int

    num_slots = packet.read_var_int
    slots = Array(WindowSlot).new(num_slots.to_i32)
    num_slots.times do |slot_number|
      begin
        slots << WindowSlot.new(slot_number.to_i32, Slot.read(packet))
      rescue ex : UnknownComponentError
        # Can't skip unknown components (unknown wire format), so fill remaining slots as empty
        Log.warn { "#{ex.message} in slot #{slot_number} of SetContainerContent (window #{window_id}). Remaining #{num_slots - slot_number - 1} slots will be empty." }
        (slot_number...num_slots).each do |i|
          slots << WindowSlot.new(i.to_i32, Slot.new)
        end
        return self.new(window_id, state_id, slots, WindowSlot.new(-1, Slot.new))
      end
    end

    begin
      cursor = WindowSlot.new -1, Slot.read(packet)
    rescue ex : UnknownComponentError
      Log.warn { "#{ex.message} in cursor slot of SetContainerContent (window #{window_id})" }
      cursor = WindowSlot.new -1, Slot.new
    end

    self.new(window_id, state_id, slots, cursor)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id # Write as VarInt
      buffer.write state_id
      buffer.write slots.size.to_u32 # Write as VarInt
      slots.each do |slot|
        slot.write(buffer) # Write the slot data (Slot.write method)
      end
      cursor.write(buffer) # Write cursor slot data
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received #{slots.size} container content for window #{window_id} state #{state_id}" }

    if window_id == 0
      slot_array = slots.map(&.as(Rosegold::Slot))
      client.inventory_menu.update_all_slots(slot_array, cursor.as(Rosegold::Slot), state_id)
    elsif client.container_menu && client.container_menu.id == window_id
      slot_array = slots.map(&.as(Rosegold::Slot))
      client.container_menu.update_all_slots(slot_array, cursor.as(Rosegold::Slot), state_id)
    else
      # Follow vanilla behavior: silently ignore packets for containers that aren't currently open
      # This is expected when containers are closed before SetContainerContent packets arrive
      container_id = client.container_menu.try(&.id) || "nil"
      Log.debug { "Ignoring SetContainerContent for mismatched window. Packet window_id=#{window_id}, client container_id=#{container_id}" }
    end
  end
end
