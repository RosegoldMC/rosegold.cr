class Rosegold::PalettedContainer
  private alias Entry = UInt16
  private alias Index = UInt32
  private alias Long = Int64

  private getter bits_per_entry : UInt8
  private getter entries_per_long : UInt8
  private getter entry_mask : Long
  private getter long_array : Array(Long)?
  private getter palette : Array(Entry)?

  # TODO read+write lock

  def initialize(io : Minecraft::IO, num_bits_direct, size = nil)
    @bits_per_entry = io.read_byte
    if bits_per_entry == 0
      @palette = [io.read_var_int.to_u16]
      @entries_per_long = 0
      @entry_mask = 0
      num_longs = io.read_var_int
      raise "Unexpected num_longs=#{num_longs} should be 0" if num_longs > 0
      @long_array = nil
      return
    end

    if bits_per_entry >= num_bits_direct
      @palette = nil # long_array stores the values directly

    else
      @palette = Array(Entry).new(io.read_var_int) { io.read_var_int.to_u16 }
    end

    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1

    num_longs = io.read_var_int
    raise "Data too short! #{num_longs} * #{entries_per_long} < #{size}" if size && num_longs * entries_per_long < size

    @long_array = Array(Long).new(num_longs) { io.read_long }
  end

  def [](index : Index) : Entry
    long_array = self.long_array
    return palette.not_nil![0] if !long_array
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    value = long_array[long_index] >> bit_offset_in_long
    value = (value & entry_mask).to_u16
    palette.try(&.[] value) || value
  end

  def []=(index : Index, value : Entry) : Nil
    palette = self.palette
    long_array = self.long_array
    if !long_array # we're storing a single value
      if palette.not_nil![0] == value
        return # nothing to do, value is already set
      else
        grow_from_single_state(index, value)
      end
    end
    entry = value
    if palette
      entry = palette.index(value) || begin
        max_palette_size = 1_u64 << bits_per_entry
        if palette.size < max_palette_size
          entry = palette.size
          palette << value
          entry
        else
          grow_palette(index, value)
        end
      end
    end
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    long = long_array.not_nil![long_index]
    long &= ~(entry_mask << bit_offset_in_long) # clear previous value
    long |= (entry.not_nil! & entry_mask) << bit_offset_in_long
    long_array.not_nil![long_index] = long
  end

  private def grow_from_single_state(index : Index, value : Entry) : Nil
    @bits_per_entry = 4_u8
    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1
    @palette = [@palette.not_nil![0], value]
    @long_array = Array(Long).new(1, 0_i64)
    self[index] = value
  end

  private def grow_palette(index : Index, value : Entry) : Nil
    @bits_per_entry += 1
    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1
    @palette.not_nil! << value
    new_long_array = Array(Long).new(long_array.not_nil!.size * 2, 0_i64)

    (0.to_u32...(long_array.not_nil!.size * entries_per_long).to_u32).each do |i|
      long_index = i // entries_per_long
      bit_offset_in_long = (i % entries_per_long) * bits_per_entry
      long = long_array.not_nil![long_index]
      long &= ~(entry_mask << bit_offset_in_long) # clear previous value
      long |= (self[i] & entry_mask) << bit_offset_in_long
      new_long_array[long_index] = long
    end

    @long_array = new_long_array
    self[index] = value
  end
end
