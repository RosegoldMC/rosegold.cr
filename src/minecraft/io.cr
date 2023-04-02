require "io/hexdump"
require "socket"
require "uuid"
require "../rosegold/world/slot"

module Minecraft::IO
  def write(value : Bool)
    write_byte value ? 1_u8 : 0_u8
  end

  def write(str : String)
    write str.bytesize.to_u32
    print str
  end

  def write_opt_string(str : String?)
    write !str.nil?
    write str unless str.nil?
  end

  def write(value : Float32 | Float64 | UInt8 | Int8)
    write_bytes value, ::IO::ByteFormat::BigEndian
  end

  # writes all bytes even for small magnitudes, not var int
  def write_full(value : UInt16 | Int16 | UInt32 | Int32 | UInt64 | Int64 | Float32 | Float64)
    write_bytes value, ::IO::ByteFormat::BigEndian
  end

  def write(uuid : UUID)
    write uuid.bytes.to_slice
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

  def write(nbt : NBT::Tag)
    raise "Not implemented" # TODO
  end

  def write(slot : Rosegold::Slot)
    write slot.empty?
    return if slot.empty?
    write slot.item_id
    write slot.count
    write slot.nbt || 0_u8
  end

  def write_angle256_deg(deg : Float32 | Float64)
    write ((deg * 256 / 360) % 256).to_i8!
  end

  def write_bit_location(x : Int32, y : Int32, z : Int32)
    x, y, z = x.to_i64, y.to_i64, z.to_i64
    write_full ((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF)
  end

  def write_bit_location(location : Rosegold::Vec3i)
    write_bit_location location.x.floor.to_i, location.y.floor.to_i, location.z.floor.to_i
  end

  def read_byte
    buf = Bytes.new 1
    read_fully(buf)
    buf[0]
  end

  def read_signed_byte
    buf = Bytes.new 1
    read_fully(buf)
    buf[0].to_i8!
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

  def read_opt_string : String?
    return nil unless read_bool
    read_var_string
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

  def read_slot : Rosegold::Slot
    return Rosegold::Slot.new unless read_bool
    Rosegold::Slot.new(read_var_int, read_byte, read_nbt)
  end

  def read_angle256_deg : Float32
    read_byte.to_f32 * 360 / 256
  end

  def read_bit_location : Vec3i
    value = read_long
    # here ordered LSB to MSB; use arithmetic shift to preserve sign
    y = ((value << 52) >> 52).to_i32 # 12 bits
    z = ((value << 26) >> 38).to_i32 # 26 bits
    x = (value >> 38).to_i32         # 26 bits
    Vec3i.new(x, y, z)
  end
end

class Minecraft::IO::Wrap < IO
  include Minecraft::IO

  def initialize(@io : ::IO); end

  def read(slice : Bytes)
    @io.read slice
  end

  def write(slice : Bytes) : Nil
    @io.write slice
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

class Minecraft::EncryptedTCPSocket < IO
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

  def read(slice : Bytes)
    upstream_size = @io.read_fully slice
    upstream = slice[0, upstream_size]
    o = @read_cipher.update upstream
    slice.copy_from o
    upstream_size
  end

  def write(slice : Bytes) : Nil
    @io.write @write_cipher.update(slice)
  end
end
