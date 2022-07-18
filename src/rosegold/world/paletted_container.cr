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
    # type checker assumes these may be changed concurrently, changing whether they are nil
    palette = self.palette
    long_array = self.long_array
    if !long_array # we're storing a single value
      if palette.not_nil![0] == value
        return # nothing to do, value is already set
      else
        raise "Growing PalettedContainer from single-state is not implemented" # TODO
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
          # the palette indices do not fit into bits_per_entry anymore
          raise "Growing PalettedContainer palette is not implemented" # TODO
        end
      end
    end
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    long = long_array[long_index]
    long &= ~(entry_mask << bit_offset_in_long) # clear previous value
    long |= (entry & entry_mask) << bit_offset_in_long
    long_array[long_index] = long
  end
end
