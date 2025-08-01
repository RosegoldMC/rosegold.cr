require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetContainerContent do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SetContainerContent[772_u32]).to eq(0x12_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::SetContainerContent.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::SetContainerContent.supports_protocol?(999_u32)).to be_false
  end

  describe "packet reading and writing" do
    let(:empty_slot) { Rosegold::Slot.new(0_u32, 0_u32) }
    let(:simple_slot) { Rosegold::Slot.new(1_u32, 1_u32) } # 1 dirt block
    let(:window_slots) { [Rosegold::WindowSlot.new(0, simple_slot)] }
    let(:cursor_slot) { Rosegold::WindowSlot.new(-1, empty_slot) }

    it "writes packet data in the correct format" do
      # Test with specific values that would expose var_int vs byte issues
      packet = Rosegold::Clientbound::SetContainerContent.new(
        window_id: 255_u8,  # Max byte value
        state_id: 300_u32,  # Value that requires var_int encoding
        slots: window_slots,
        cursor: cursor_slot
      )

      written_bytes = packet.write
      io = Minecraft::IO::Memory.new(written_bytes)

      # Check packet structure manually
      packet_id = io.read_byte
      expect(packet_id).to eq(0x12_u8)

      # window_id should be written as byte (according to read method)
      window_id = io.read_byte
      expect(window_id).to eq(255_u8)

      # state_id should be written as var_int (according to read method)
      state_id = io.read_var_int
      expect(state_id).to eq(300_u32)

      # slots count should be written as var_int (according to read method)
      slots_count = io.read_var_int
      expect(slots_count).to eq(1_u32)

      # Verify that the slot data can be read properly
      # Each slot in the array
      slot_count = io.read_var_int
      expect(slot_count).to eq(1_u32)  # simple_slot has count 1

      item_id = io.read_var_int
      expect(item_id).to eq(1_u32)  # simple_slot has item_id 1

      # component counts 
      components_to_add_count = io.read_var_int
      expect(components_to_add_count).to eq(0_u32)  # simple_slot has no components

      components_to_remove_count = io.read_var_int
      expect(components_to_remove_count).to eq(0_u32)  # simple_slot has no components

      # Now read cursor slot data
      cursor_count = io.read_var_int
      expect(cursor_count).to eq(0_u32)  # cursor is empty
    end

    it "writes WindowSlot data correctly" do
      # Test that WindowSlot.write works - if this method doesn't exist,
      # it should fail to compile or behave incorrectly
      slot = Rosegold::WindowSlot.new(5, Rosegold::Slot.new(2_u32, 3_u32))
      io = Minecraft::IO::Memory.new
      
      # This should delegate to Slot.write
      slot.write(io)
      
      written_data = io.to_slice
      read_io = Minecraft::IO::Memory.new(written_data)
      
      count = read_io.read_var_int
      expect(count).to eq(2_u32)
      
      item_id = read_io.read_var_int
      expect(item_id).to eq(3_u32)
    end

    it "compares buffer.write slot vs slot.write buffer" do
      # Test both approaches to see if they produce the same results
      slot = Rosegold::WindowSlot.new(0, Rosegold::Slot.new(1_u32, 1_u32))
      
      # Approach 1: buffer.write slot (like WindowItems)
      io1 = Minecraft::IO::Memory.new
      io1.write slot
      result1 = io1.to_slice
      
      # Approach 2: slot.write buffer (like SetContainerContent)
      io2 = Minecraft::IO::Memory.new
      slot.write(io2)
      result2 = io2.to_slice
      
      # Both should produce identical results
      expect(result1).to eq(result2)
    end

    it "reads and writes packet data correctly" do
      # Create a SetContainerContent packet
      packet = Rosegold::Clientbound::SetContainerContent.new(
        window_id: 1_u8,
        state_id: 123_u32,
        slots: window_slots,
        cursor: cursor_slot
      )

      # Write the packet
      written_bytes = packet.write

      # Create an IO buffer from the written bytes
      io = Minecraft::IO::Memory.new(written_bytes)
      
      # Skip the packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x12_u8)

      # Read the packet back
      read_packet = Rosegold::Clientbound::SetContainerContent.read(io)

      # Verify the data matches
      expect(read_packet.window_id).to eq(1_u8)
      expect(read_packet.state_id).to eq(123_u32)
      expect(read_packet.slots.size).to eq(1)
      expect(read_packet.slots[0].slot_number).to eq(0)
      expect(read_packet.slots[0].count).to eq(1_u32)
      expect(read_packet.cursor.slot_number).to eq(-1)
      expect(read_packet.cursor.count).to eq(0_u32)
    end

    it "handles empty container correctly" do
      # Create a packet with no slots
      packet = Rosegold::Clientbound::SetContainerContent.new(
        window_id: 0_u8,
        state_id: 0_u32,
        slots: [] of Rosegold::WindowSlot,
        cursor: cursor_slot
      )

      # Write and read back
      written_bytes = packet.write
      io = Minecraft::IO::Memory.new(written_bytes)
      
      # Skip packet ID
      io.read_byte
      
      read_packet = Rosegold::Clientbound::SetContainerContent.read(io)

      expect(read_packet.window_id).to eq(0_u8)
      expect(read_packet.state_id).to eq(0_u32)
      expect(read_packet.slots.size).to eq(0)
      expect(read_packet.cursor.count).to eq(0_u32)
    end

    it "handles multiple slots correctly" do
      multiple_slots = [
        Rosegold::WindowSlot.new(0, simple_slot),
        Rosegold::WindowSlot.new(1, empty_slot),
        Rosegold::WindowSlot.new(2, simple_slot)
      ]

      packet = Rosegold::Clientbound::SetContainerContent.new(
        window_id: 2_u8,
        state_id: 456_u32,
        slots: multiple_slots,
        cursor: cursor_slot
      )

      written_bytes = packet.write
      io = Minecraft::IO::Memory.new(written_bytes)
      
      # Skip packet ID
      io.read_byte
      
      read_packet = Rosegold::Clientbound::SetContainerContent.read(io)

      expect(read_packet.slots.size).to eq(3)
      expect(read_packet.slots[0].count).to eq(1_u32)
      expect(read_packet.slots[1].count).to eq(0_u32)
      expect(read_packet.slots[2].count).to eq(1_u32)
    end
  end
end