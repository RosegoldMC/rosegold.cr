# Four modes:
# Single state: All entries are the same value. The value is stored as palette[0]. The long_array is empty.
# Encoded: The long_array stores the palette index of each value.
# Direct: The long_array stores values directly. The palette is empty.
class Rosegold::PalettedContainer
  private alias Entry = UInt16
  private alias Index = UInt32
  private alias Long = UInt64

  getter size : Index
  private getter bits_per_entry : UInt8
  private getter entries_per_long : UInt8
  private getter entry_mask : Long
  private getter long_array : Array(Long)
  private getter palette : Array(Entry)

  # TODO read+write lock

  # Creates a container filled with air/default values (ID 0)
  def self.air_filled(size : Index) : PalettedContainer
    new(size: size, empty: true)
  end

  def initialize(size : Index, empty : Bool)
    @size = size
    @bits_per_entry = 0_u8 # single state mode
    @palette = [0_u16]     # air block/biome (ID 0)
    @entries_per_long = 0_u8
    @entry_mask = 0_u64
    @long_array = [] of Long
  end

  def initialize(io : Minecraft::IO, num_bits_direct, @size)
    @bits_per_entry = io.read_byte
    if bits_per_entry == 0 # single state mode
      @palette = [io.read_var_int.to_u16]
      @entries_per_long = 0
      @entry_mask = 0
      @long_array = Array(Long).new(0)

      return
    end

    if bits_per_entry >= num_bits_direct # direct mode
      @palette = [] of Entry
    else # linear
      @palette = Array(Entry).new(io.read_var_int) { io.read_var_int.to_u16 }
    end

    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_u64 << bits_per_entry) - 1

    num_longs = (size + entries_per_long - 1) // entries_per_long
    @long_array = Array(Long).new(num_longs) { io.read_long.to_u64! }
  end

  def write(io : Minecraft::IO)
    io.write bits_per_entry
    if bits_per_entry == 0
      io.write palette[0]
      # As of MC 1.21.5, array length is not sent (calculated)
      return
    end
    unless palette.empty?
      io.write palette.size
      palette.each { |id| io.write id }
    end
    # As of MC 1.21.5, array length is not sent (calculated)
    long_array.each { |id| io.write_full id }
  end

  def [](index : Index) : Entry
    long_array = self.long_array
    if long_array.empty? # single state mode
      return palette[0]
    end

    # Add bounds checking for MC 1.21+ compatibility
    return 0_u16 if index >= size # Return air block for out-of-bounds access

    long_index = index // entries_per_long
    return 0_u16 if long_index >= long_array.size # Return air block for out-of-bounds array access

    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    value = long_array[long_index] >> bit_offset_in_long
    value = (value & entry_mask).to_u16
    return value if palette.empty? # direct mode

    # Add bounds checking for palette access
    return 0_u16 if value >= palette.size # Return air block for out-of-bounds palette access
    palette[value]                        # encoded mode
  end

  def []=(index : Index, value : Entry) : Nil
    if long_array.empty? # single state mode
      if palette[0] == value
        return # nothing to do, value is already set
      else
        grow_from_single_state
        # After growing from single state, restart the operation
        self[index] = value
        return
      end
    end
    if palette.empty? # direct mode
      encoded = value
    else # encoded mode
      encoded = palette.index(value)
      unless encoded
        max_palette_size = 1_u64 << bits_per_entry
        if palette.size + 1 >= max_palette_size
          grow_palette
          # After growing, we need to try again since the palette structure may have changed
          self[index] = value
          return
        end
        encoded = palette.size
        palette << value
      end
    end
    encoded = encoded.to_u64!
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    long = long_array[long_index]
    long &= ~(entry_mask << bit_offset_in_long) # clear previous value
    long |= (encoded & entry_mask) << bit_offset_in_long
    long_array[long_index] = long
  end

  private def grow_from_single_state : Nil
    @bits_per_entry = 4_u8
    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_u64 << bits_per_entry) - 1
    num_longs = (size + entries_per_long - 1) // entries_per_long
    @long_array = Array(Long).new(num_longs, 0_u64)
    # all values will be 0, and our single value is also at palette index 0
  end

  private def grow_palette : Nil
    new_bits_per_entry = bits_per_entry + 1
    new_entries_per_long = 64_u8 // new_bits_per_entry
    new_entry_mask = (1_u64 << new_bits_per_entry) - 1
    new_num_longs = (size + new_entries_per_long - 1) // new_entries_per_long
    new_long_array = Array(Long).new(new_num_longs, 0_u64)

    # Java copyFrom implementation: iterate through the actual storage size (which is always `size`)
    # and use the accessor methods to handle bit manipulation
    (0_u32...size).each do |i|
      # Get the encoded value using our current accessor (which handles the bit manipulation)
      # Note: we can't use self[i] because that returns the decoded value if the palette is in effect
      old_long_index = i // entries_per_long
      break if old_long_index >= long_array.size # Safety check

      old_bit_offset_in_long = (i % entries_per_long) * bits_per_entry
      encoded_value = long_array[old_long_index] >> old_bit_offset_in_long
      encoded_value = (encoded_value & entry_mask).to_u16

      # Store in new array using similar bit manipulation
      new_long_index = i // new_entries_per_long
      break if new_long_index >= new_long_array.size # Safety check

      new_bit_offset_in_long = (i % new_entries_per_long) * new_bits_per_entry
      new_long_array[new_long_index] |= (encoded_value.to_u64 & new_entry_mask) << new_bit_offset_in_long
    end

    @bits_per_entry = new_bits_per_entry
    @entries_per_long = new_entries_per_long
    @entry_mask = new_entry_mask
    @long_array = new_long_array
  end
end
