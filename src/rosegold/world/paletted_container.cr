class Rosegold::PalettedContainer
  private alias Entry = UInt16
  private alias Index = UInt32
  private alias Long = Int64

  private getter num_entries : Index
  private getter bits_per_entry : UInt8
  private getter entries_per_long : UInt8
  private getter entry_mask : Long
  private getter long_array : Array(Long)
  private getter palette : Array(Entry)

  # TODO read+write lock

  def initialize(io : Minecraft::IO, num_bits_direct, @num_entries)
    @bits_per_entry = io.read_byte
    if bits_per_entry == 0
      @palette = [io.read_var_int.to_u16]
      @entries_per_long = 0
      @entry_mask = 0
      num_longs = io.read_var_int
      raise "Unexpected num_longs=#{num_longs} should be 0" if num_longs > 0
      @long_array = [] of Long
      return
    end

    if bits_per_entry >= num_bits_direct
      @palette = [] of Entry
    else
      @palette = Array(Entry).new(io.read_var_int) { io.read_var_int.to_u16 }
    end

    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1

    num_longs = io.read_var_int
    raise "Data too short! #{num_longs} * #{entries_per_long} < #{num_entries}" if num_longs * entries_per_long < num_entries

    @long_array = Array(Long).new(num_longs) { io.read_long }
  end

  def [](index : Index) : Entry
    long_array = self.long_array
    return palette.[0] if long_array.empty?
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    value = long_array[long_index] >> bit_offset_in_long
    value = (value & entry_mask).to_u16
    palette.try(&.[] value) || value
  end

  def []=(index : Index, value : Entry) : Nil
    palette = self.palette
    long_array = self.long_array
    if long_array.empty? # we're storing a single value
      if palette[0] == value
        return # nothing to do, value is already set
      else
        grow_from_single_state
      end
    end
    if palette.empty?
      entry = value
    else
      entry = palette.index(value) || begin
        max_palette_size = 1_u64 << bits_per_entry
        if palette.size >= max_palette_size
          grow_palette
        end
        entry = palette.size
        palette << value
        entry
      end
    end
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    long = long_array[long_index]
    long &= ~(entry_mask << bit_offset_in_long) # clear previous value
    long |= (entry & entry_mask) << bit_offset_in_long
    long_array[long_index] = long
  end

  private def grow_from_single_state : Nil
    @bits_per_entry = 4_u8
    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1
    @long_array = Array(Long).new(1, 0_i64)
  end

  private def grow_palette : Nil
    new_bits_per_entry = bits_per_entry + 1
    new_entries_per_long = 64_u8 // new_bits_per_entry
    new_entry_mask = (1_i64 << new_bits_per_entry) - 1
    new_long_array = Array(Long).new((num_entries / new_entries_per_long).ceil.to_i, 0_i64)

    (0_u32...num_entries).each do |i|
      long_index = i // new_entries_per_long
      bit_offset_in_long = (i % new_entries_per_long) * new_bits_per_entry
      long = new_long_array[long_index]
      # no need to zero-out previous value's bits, are already 0
      long |= (self[i] & new_entry_mask) << bit_offset_in_long
      new_long_array[long_index] = long
    end

    @bits_per_entry = new_bits_per_entry
    @entries_per_long = new_entries_per_long
    @entry_mask = new_entry_mask
    @long_array = new_long_array
  end
end
