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
    @palette = [0_u16] # air block/biome (ID 0)
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
      num_longs = io.read_var_int
      raise "Unexpected num_longs=#{num_longs} should be 0" if num_longs > 0
      @long_array = [] of Long
      return
    end

    if bits_per_entry >= num_bits_direct # direct mode
      @palette = [] of Entry
    else # encoded mode
      @palette = Array(Entry).new(io.read_var_int) { io.read_var_int.to_u16 }
    end

    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_u64 << bits_per_entry) - 1

    num_longs = io.read_var_int
    raise "Data too short! #{num_longs} * #{entries_per_long} < #{size}" if num_longs * entries_per_long < size

    @long_array = Array(Long).new(num_longs) { io.read_long.to_u64! }
  end

  def write(io : Minecraft::IO)
    io.write bits_per_entry
    if bits_per_entry == 0
      io.write palette[0]
      io.write 0_i32
      return
    end
    unless palette.empty?
      io.write palette.size
      palette.each { |id| io.write id }
    end
    io.write long_array.size
    long_array.each { |id| io.write_full id }
  end

  def [](index : Index) : Entry
    long_array = self.long_array
    return palette[0] if long_array.empty? # single state mode
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    value = long_array[long_index] >> bit_offset_in_long
    value = (value & entry_mask).to_u16
    return value if palette.empty? # direct mode

    palette[value] # encoded mode
  end

  def []=(index : Index, value : Entry) : Nil
    if long_array.empty? # single state mode
      if palette[0] == value
        return # nothing to do, value is already set
      else
        grow_from_single_state
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
        end
        encoded = palette.size
        palette << value
        encoded
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
    @long_array = Array(Long).new(size*4//64, 0_u64)
    # all values will be 0, and our single value is also at palette index 0
    Log.debug { "Growing PalettedContainer from single state. Array length: #{@long_array.size}" }
  end

  private def grow_palette : Nil
    new_bits_per_entry = bits_per_entry + 1
    new_entries_per_long = 64_u8 // new_bits_per_entry
    new_entry_mask = (1_u64 << new_bits_per_entry) - 1
    new_num_longs = (size / new_entries_per_long).ceil.to_i
    new_long_array = Array(Long).new(new_num_longs, 0_u64)

    (0_u32...size).each do |i|
      # read from old array
      # note that we can't use self[i] because that returns the decoded value if the palette is in effect, but we want the encoded value
      old_long_index = i // entries_per_long
      old_bit_offset_in_long = (i % entries_per_long) * bits_per_entry
      value = long_array[old_long_index] >> old_bit_offset_in_long
      value = (value & entry_mask).to_u16
      # write to new array
      long_index = i // new_entries_per_long
      new_bit_offset_in_long = (i % new_entries_per_long) * new_bits_per_entry
      long = new_long_array[long_index]
      # no need to zero-out previous value's bits, are already 0
      long |= (value & new_entry_mask) << new_bit_offset_in_long
      new_long_array[long_index] = long
    end

    @bits_per_entry = new_bits_per_entry
    @entries_per_long = new_entries_per_long
    @entry_mask = new_entry_mask
    @long_array = new_long_array
    Log.debug { "Growing PalettedContainer. Array length: #{@long_array.size}, Palette length: #{@palette.size}" }
  end
end
