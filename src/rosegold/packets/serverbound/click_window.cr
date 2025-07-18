require "../packet"

class Rosegold::Serverbound::ClickWindow < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x08_u8, # MC 1.18
    767_u32 => 0x08_u8, # MC 1.21
    771_u32 => 0x08_u8, # MC 1.21.6
  })

  enum Mode
    Click; Shift; Swap; Middle; Drop; Drag; Double
  end

  property window_id : UInt8
  property state_id : Int32
  property slot_number : Int16
  property button : Int8
  property mode : Mode
  property changed_slots : Array(WindowSlot)
  property cursor : Slot

  def initialize(@mode, @button, @slot_number, @changed_slots, @window_id, @state_id, @cursor); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
      buffer.write state_id
      buffer.write_full slot_number
      buffer.write button
      buffer.write mode.value
      buffer.write changed_slots.size
      changed_slots.each do |slot|
        buffer.write_full slot.slot_number.to_i16
        buffer.write slot
      end
      buffer.write cursor
    end.to_slice
  end

  # Hotbar starts at 0.
  def self.swap_hotbar(window, hotbar_nr, slot_number)
    self.new Mode::Swap, hotbar_nr, slot_number, window
  end

  def self.swap_off_hand(window, slot_number)
    self.new :swap, 40, slot_number, window
  end

  def self.click(window, slot_number, right = false, shift = false, double = false)
    right_nr = right ? 1_u8 : 0_u8
    if double
      self.new :double, 0, slot_number, window
    elsif shift
      self.new :shift, right_nr, slot_number, window
    else
      self.new :click, right_nr, slot_number, window
    end
  end

  def self.drop(window, slot_number, stack_mode : StackMode)
    case stack_mode
    when :single
      self.new :drop, 0, slot_number, window
    when :full
      self.new :drop, 1, slot_number, window
    else
      raise "Invalid stack mode: #{stack_mode}"
    end
  end

  def self.drop_cursor(window, stack_mode : StackMode)
    case stack_mode
    when :full
      self.new :click, 0, -999, window
    when :single
      self.new :click, 1, -999, window
    else
      raise "Invalid stack mode: #{stack_mode}"
    end
  end

  enum StackMode
    Single; Full
  end

  private def self.new(mode : Mode, button, slot_number, window)
    changed_slots = [] of WindowSlot # TODO
    self.new mode, button.to_i8, slot_number.to_i16,
      changed_slots, window.id.to_u8, window.state_id.to_i16, window.cursor
  end
end