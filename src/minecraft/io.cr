require "io/hexdump"
require "socket"
require "uuid"
require "../rosegold/inventory/slot"
require "../rosegold/world/vec3"
require "../rosegold/models/text_component"

# Represents a Minecraft protocol angle (0-255 representing 0-360 degrees)
struct Minecraft::Angle
  property degrees : Float32

  def initialize(@degrees : Float32 | Float64)
    @degrees = @degrees.to_f32
  end

  def to_f32
    @degrees
  end

  def to_f64
    @degrees.to_f64
  end
end

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
    # Convert signed types to unsigned to avoid arithmetic right shift
    # keeping two's complement bit pattern (what Minecraft VarInt expects)
    unsigned = case value
               when Int16 then value.unsafe_as(UInt16).to_u64
               when Int32 then value.unsafe_as(UInt32).to_u64
               when Int64 then value.unsafe_as(UInt64)
               else            value.to_u64
               end
    a = Array(UInt8).new
    more = true
    while more
      b = (unsigned & 0x7F).to_u8
      unsigned >>= 7
      if unsigned == 0
        more = false
      else
        b |= 0x80
      end

      a << b
    end
    write a.to_unsafe.to_slice a.size
  end

  def write(nbt : NBT::Tag)
    nbt.write_named self
  end

  def write(slot : Rosegold::Slot)
    slot.write self
  end

  def write(text_component : Rosegold::TextComponent)
    text_component.write self
  end

  def write_angle256_deg(deg : Float32 | Float64)
    write ((deg * 256 / 360) % 256).to_i8!
  end

  def write(angle : Minecraft::Angle)
    write_angle256_deg(angle.degrees)
  end

  def write(x : Int32, y : Int32, z : Int32)
    x, y, z = x.to_i64, y.to_i64, z.to_i64
    write_full ((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF)
  end

  def write(location : Rosegold::Vec3i)
    write location.x.floor.to_i, location.y.floor.to_i, location.z.floor.to_i
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

  def read_nbt_unamed : Minecraft::NBT::Tag
    NBT::Tag.read(self)
  end

  def read_angle256_deg : Float32
    read_byte.to_f32 * 360 / 256
  end

  # Read LpVec3 (packed velocity format used in 1.21.11+)
  # See decompiled net.minecraft.network.LpVec3 for reference
  def read_lp_vec3 : {Float64, Float64, Float64}
    first_byte = read_byte
    if first_byte == 0x00
      return {0.0, 0.0, 0.0}
    end

    second_byte = read_byte
    hi = read_bytes(UInt32, ::IO::ByteFormat::BigEndian).to_u64
    bits = (hi << 16) | (second_byte.to_u64 << 8) | first_byte.to_u64

    packed_x = (bits >> 3) & 0x7FFF_u64
    packed_y = (bits >> 18) & 0x7FFF_u64
    packed_z = (bits >> 33) & 0x7FFF_u64
    continuation = (bits >> 2) & 1_u64
    scale = (first_byte & 0x3).to_u64

    if continuation == 1
      extra = read_var_int.to_u32.to_u64
      scale = scale | (extra << 2)
    end

    x = unpack_lp_component(packed_x) * scale.to_f64
    y = unpack_lp_component(packed_y) * scale.to_f64
    z = unpack_lp_component(packed_z) * scale.to_f64
    {x, y, z}
  end

  private def unpack_lp_component(value : UInt64) : Float64
    clamped = Math.min(value & 0x7FFF_u64, 32766_u64).to_f64
    clamped * 2.0 / 32766.0 - 1.0
  end

  ABS_MAX_LP_VEC3 =      1.7179869183e10
  ABS_MIN_LP_VEC3 = 3.051944088384301e-5

  # Write LpVec3 (packed velocity format used in 1.21.11+)
  def write_lp_vec3(vx : Float64, vy : Float64, vz : Float64)
    max_abs = Math.max(vx.abs, Math.max(vy.abs, vz.abs))
    if max_abs < ABS_MIN_LP_VEC3
      write 0x00_u8
      return
    end

    scale = max_abs.ceil.to_i64
    scale = Math.max(scale, 1_i64)

    px = pack_lp_component(vx, scale.to_f64)
    py = pack_lp_component(vy, scale.to_f64)
    pz = pack_lp_component(vz, scale.to_f64)

    continuation = (scale & 0x3) != scale ? 1_u64 : 0_u64
    low_scale_bits = scale.to_u64 & 0x3_u64

    bits = low_scale_bits |
           (continuation << 2) |
           (px << 3) |
           (py << 18) |
           (pz << 33)

    # Write 2 bytes (byte1, byte2)
    write (bits & 0xFF).to_u8
    write ((bits >> 8) & 0xFF).to_u8
    # Write 4 bytes big-endian
    write_bytes(((bits >> 16) & 0xFFFFFFFF_u64).to_u32, ::IO::ByteFormat::BigEndian)

    if continuation == 1
      write (scale >> 2).to_u32
    end
  end

  private def pack_lp_component(value : Float64, scale : Float64) : UInt64
    normalized = scale > 0.0 ? value / scale : 0.0
    packed = ((normalized * 0.5 + 0.5) * 32766.0).round.to_i64
    packed = packed.clamp(0_i64, 32766_i64)
    packed.to_u64
  end

  def read_bit_location : Rosegold::Vec3i
    value = read_long
    # here ordered LSB to MSB; use arithmetic shift to preserve sign
    y = ((value << 52) >> 52).to_i32 # 12 bits
    z = ((value << 26) >> 38).to_i32 # 26 bits
    x = (value >> 38).to_i32         # 26 bits
    Rosegold::Vec3i.new(x, y, z)
  end

  def read_text_component : Rosegold::TextComponent
    Rosegold::TextComponent.read(self)
  rescue ex : Minecraft::NBT::DecodeError
    Log.warn { "Malformed text component NBT (#{ex.message}); substituting placeholder" }
    Rosegold::TextComponent.new("")
  end
end

class Minecraft::IO::Wrap < IO
  include Minecraft::IO

  def initialize(@io : ::IO); end

  delegate close, closed?, flush, peek, to: @io

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

class Minecraft::IO::CaptureIO < IO
  include Minecraft::IO

  getter buffer : ::IO::Memory = ::IO::Memory.new

  def initialize(@inner : ::IO)
  end

  def read(slice : Bytes) : Int32
    bytes_read = @inner.read(slice)
    @buffer.write(slice[0, bytes_read]) if bytes_read > 0
    bytes_read
  end

  def write(slice : Bytes) : Nil
    @inner.write(slice)
  end
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

  delegate close, closed?, flush, to: @io

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
