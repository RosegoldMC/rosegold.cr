require "../../minecraft/io"

class Rosegold::LightData
  property sky_light_mask : Array(UInt64)
  property block_light_mask : Array(UInt64)
  property empty_sky_light_mask : Array(UInt64)
  property empty_block_light_mask : Array(UInt64)
  property sky_light_arrays : Array(Bytes)
  property block_light_arrays : Array(Bytes)

  def initialize(
    @sky_light_mask = [] of UInt64,
    @block_light_mask = [] of UInt64,
    @empty_sky_light_mask = [] of UInt64,
    @empty_block_light_mask = [] of UInt64,
    @sky_light_arrays = [] of Bytes,
    @block_light_arrays = [] of Bytes,
  )
  end

  def self.read(io)
    # Read Sky Light Mask (BitSet)
    sky_light_mask_length = io.read_var_int
    sky_light_mask = Array(UInt64).new(sky_light_mask_length) { io.read_long.to_u64 }

    # Read Block Light Mask (BitSet)
    block_light_mask_length = io.read_var_int
    block_light_mask = Array(UInt64).new(block_light_mask_length) { io.read_long.to_u64 }

    # Read Empty Sky Light Mask (BitSet)
    empty_sky_light_mask_length = io.read_var_int
    empty_sky_light_mask = Array(UInt64).new(empty_sky_light_mask_length) { io.read_long.to_u64 }

    # Read Empty Block Light Mask (BitSet)
    empty_block_light_mask_length = io.read_var_int
    empty_block_light_mask = Array(UInt64).new(empty_block_light_mask_length) { io.read_long.to_u64 }

    # Read Sky Light arrays
    sky_light_arrays = [] of Bytes
    sky_light_mask.each_with_index do |mask, _|
      64.times do |bit|
        if (mask & (1_u64 << bit)) != 0
          array_length = io.read_var_int
          array_data = Bytes.new(array_length)
          io.read_fully(array_data)
          sky_light_arrays << array_data
        end
      end
    end

    # Read Block Light arrays
    block_light_arrays = [] of Bytes
    block_light_mask.each_with_index do |mask, _|
      64.times do |bit|
        if (mask & (1_u64 << bit)) != 0
          array_length = io.read_var_int
          array_data = Bytes.new(array_length)
          io.read_fully(array_data)
          block_light_arrays << array_data
        end
      end
    end

    new(sky_light_mask, block_light_mask, empty_sky_light_mask, empty_block_light_mask, sky_light_arrays, block_light_arrays)
  end

  def write(io)
    # Write Sky Light Mask (BitSet)
    io.write(sky_light_mask.size.to_u32)
    sky_light_mask.each { |mask| io.write_full(mask.to_i64) }

    # Write Block Light Mask (BitSet)
    io.write(block_light_mask.size.to_u32)
    block_light_mask.each { |mask| io.write_full(mask.to_i64) }

    # Write Empty Sky Light Mask (BitSet)
    io.write(empty_sky_light_mask.size.to_u32)
    empty_sky_light_mask.each { |mask| io.write_full(mask.to_i64) }

    # Write Empty Block Light Mask (BitSet)
    io.write(empty_block_light_mask.size.to_u32)
    empty_block_light_mask.each { |mask| io.write_full(mask.to_i64) }

    # Write Sky Light arrays
    sky_light_arrays.each do |array|
      io.write(array.size.to_u32)
      io.write(array)
    end

    # Write Block Light arrays
    block_light_arrays.each do |array|
      io.write(array.size.to_u32)
      io.write(array)
    end
  end

  def to_bytes : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      write(io)
    end.to_slice
  end
end
