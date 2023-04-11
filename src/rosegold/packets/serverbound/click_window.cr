require "../packet"

class Rosegold::Serverbound::ClickWindow < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x08_u8

  enum Mode
    Click; Shift; Swap; Middle; Drop; Drag; Double
  end

  property window_id : UInt8
  property state_id : UInt32
  property slot_nr : UInt16
  property button : UInt8
  property mode : Mode
  property changed_slots : Array(WindowSlot)
  property cursor : Slot

  def initialize(@mode, @button, @slot_nr, @changed_slots, @window_id, @state_id, @cursor); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write window_id
      buffer.write state_id
      buffer.write_full slot_nr
      buffer.write button
      buffer.write mode.value
      buffer.write changed_slots.size
      changed_slots.each do |slot|
        buffer.write_full slot.slot_nr.to_u16
        buffer.write slot
      end
      buffer.write cursor
    end.to_slice
  end

  # Hotbar starts at 0.
  def self.swap_hotbar(window, hotbar_nr, slot_nr)
    self.new Mode::Swap, hotbar_nr, slot_nr, window
  end

  def self.swap_off_hand(window, slot_nr)
    self.new :swap, 40, slot_nr, window
  end

  def self.click(window, slot_nr, right = false, shift = false, double = false)
    right_nr = right ? 1_u8 : 0_u8
    if double
      self.new :double, 0, slot_nr, window
    elsif shift
      self.new :shift, right_nr, slot_nr, window
    else
      self.new :click, right_nr, slot_nr, window
    end
  end

  def self.drop(window, slot_nr, stack_mode : StackMode)
    case stack_mode
    when :single
      self.new :drop, 0, slot_nr, window
    when :full
      self.new :drop, 1, slot_nr, window
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

  private def self.new(mode : Mode, button, slot_nr, window)
    changed_slots = [] of WindowSlot # TODO
    self.new mode, button.to_u8, slot_nr.to_u16,
      changed_slots, window.id.to_u8, window.state_id, window.cursor
  end
end
