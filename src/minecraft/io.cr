require "io/hexdump"
require "socket"
require "uuid"

module Minecraft::IO
  def write(value : Bool)
    write_byte value ? 1_u8 : 0_u8
  end

  def write(value : String)
    write value.bytesize.to_u32
    print value
  end

  def write(value : Float32 | Float64 | UInt8)
    write_bytes value, ::IO::ByteFormat::BigEndian
  end

  # writes all bytes even for small magnitudes, not var int
  def write_full(value : UInt16 | Int16 | UInt32 | Int32 | UInt64 | Int64)
    write_bytes value, ::IO::ByteFormat::BigEndian
  end

  # writes var int
  def write(value : UInt16 | Int16 | UInt32 | Int32 | UInt64 | Int64)
    a = Array(UInt8).new
    more = true
    while more
      b = (value & 0x7F).to_u8
      value >>= 7
      if value == 0
        more = false
      else
        b |= 0x80
      end

      a << b
    end
    write a.to_unsafe.to_slice a.size
  end

  def write_position(x : Int32, y : Int32, z : Int32)
    x, y, z = x.to_i64, y.to_i64, z.to_i64
    write_full ((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF)
  end

  def write(position : Rosegold::Vec3d)
    write_position position.x.floor.to_i, position.y.floor.to_i, position.z.floor.to_i
  end

  def write(position : Tuple(Int32, Int32, Int32))
    write_position position[0], position[1], position[2]
  end

  def read_byte
    buf = Bytes.new 1
    read_fully(buf)
    buf[0]
  end

  def read_bool
    read_byte != 0
  end

  def read_float : Float32
    read_bytes Float32, ::IO::ByteFormat::BigEndian
  end

  def read_double : Float64
    read_bytes Float64, ::IO::ByteFormat::BigEndian
  end

  def read_ushort : UInt16
    read_bytes UInt16, ::IO::ByteFormat::BigEndian
  end

  def read_short : Int16
    read_bytes Int16, ::IO::ByteFormat::BigEndian
  end

  def read_int : Int32
    read_bytes Int32, ::IO::ByteFormat::BigEndian
  end

  def read_long : Int64
    read_bytes Int64, ::IO::ByteFormat::BigEndian
  end

  def read_var_int : UInt32
    result = 0_u32
    shift = 0
    loop do
      b = read_byte
      result |= ((0x7F & b).to_u32) << shift
      return result if b & 0x80 == 0
      shift += 7
      raise "VarInt is too big: #{shift}" if shift >= 32
    end
  end

  def read_var_long : UInt64
    result = 0_u64
    shift = 0
    loop do
      b = read_byte
      result |= ((0x7F & b).to_u64) << shift
      return result if b & 0x80 == 0
      shift += 7
      raise "VarLong is too big: #{shift}" if shift >= 64
    end
  end

  def read_var_string : String
    read_var_string(read_var_int)
  end

  def read_var_string(size : UInt32) : String
    buffer = Bytes.new size
    read buffer

    String.new(buffer)
  end

  def read_var_bytes : Bytes
    buffer = Bytes.new read_var_int
    read buffer

    buffer
  end

  def read_uuid : UUID
    read_fully(buffer = Bytes.new(16))
    UUID.new buffer
  end

  def read_nbt : Minecraft::NBT::Tag
    NBT::Tag.read_named(self)[1]
  end

  def read_position : Tuple(Int32, Int32, Int32)
    value = read_long
    # here ordered LSB to MSB; use arithmetic shift to preserve sign
    y = ((value << 52) >> 52).to_i32 # 12 bits
    z = ((value << 26) >> 38).to_i32 # 26 bits
    x = (value >> 38).to_i32         # 26 bits
    {x, y, z}
  end
end

class Minecraft::IO::Memory < IO::Memory
  include Minecraft::IO
end

class Minecraft::IO::Hexdump < IO::Hexdump
  include Minecraft::IO
end

class Minecraft::TCPSocket < TCPSocket
  include Minecraft::IO
end

class Minecraft::EncryptedTCPSocket
  include Minecraft::IO

  getter read_cipher : OpenSSL::Cipher
  getter write_cipher : OpenSSL::Cipher

  def initialize(@io : IO, cipher_method : String, iv : Bytes, key : Bytes)
    @read_cipher = OpenSSL::Cipher.new cipher_method
    @read_cipher.decrypt
    @read_cipher.key = key
    @read_cipher.iv = iv
    @write_cipher = OpenSSL::Cipher.new cipher_method
    @write_cipher.encrypt
    @write_cipher.key = key
    @write_cipher.iv = iv
  end

  def read_fully(slice : Bytes)
    upstream_size = @io.read_fully slice
    upstream = slice[0, upstream_size]
    o = @read_cipher.update upstream
    slice.copy_from o
    upstream_size
  end

  def write(slice : Bytes) : Nil
    @io.write @write_cipher.update(slice)
  end

  def flush
    @io.flush
  end
end
