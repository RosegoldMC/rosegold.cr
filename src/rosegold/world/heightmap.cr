require "../../minecraft/io"

# Represents a heightmap structure as defined in the protocol
class Rosegold::Heightmap
  property type : UInt32
  property data : Array(Int64)

  def initialize(@type = 0_u32, @data = [] of Int64)
  end

  def self.read(io)
    type = io.read_var_int
    data_length = io.read_var_int
    data = Array(Int64).new(data_length) { io.read_long }
    new(type, data)
  end

  def write(io)
    io.write(type)
    io.write(data.size.to_u32)
    data.each { |long| io.write_full(long) }
  end

  def to_bytes : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      write(io)
    end.to_slice
  end
end