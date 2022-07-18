class Rosegold::PalettedContainer
  private getter bits_per_entry : UInt8
  private getter entries_per_long : UInt8
  private getter entry_mask : Int64
  private getter long_array : Array(Int64)?
  private getter palette : Array(UInt16)?

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
      @palette = Array(UInt16).new(io.read_var_int) { io.read_var_int.to_u16 }
    end

    @entries_per_long = 64_u8 // bits_per_entry
    @entry_mask = (1_i64 << bits_per_entry) - 1

    num_longs = io.read_var_int
    raise "Data too short! #{num_longs} * #{entries_per_long} < #{size}" if size && num_longs * entries_per_long < size

    @long_array = Array(Int64).new(num_longs) { io.read_long }
  end

  def [](index : UInt32) : UInt16
    return palette.not_nil![0] if long_array.is_nil?
    long_index = index // entries_per_long
    bit_offset_in_long = (index % entries_per_long) * bits_per_entry
    value = long_array[long_index] >> bit_offset_in_long
    value = (value & entry_mask).to_u16
    palette.try(&.[] value) || value
  end

  def []=(index : UInt32, value : UInt16)
    if !palette
      entry = value
    else
      entry = palette.index value
      if entry.is_nil?
        max_palette_size = 1_i64 << bits_per_entry
        if palette.size < max_palette_size
          entry = palette.size
          palette << value
        else
          # the palette indices do not fit into bits_per_entry anymore
          raise "Growing PalettedContainer is not implemented" # TODO
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
