require "socket"
require "uuid"

module Minecraft::IO
  def write(value : String)
    write value.bytesize.to_u32
    print value
  end

  def write_var_bytes(bytes : Bytes)
    write bytes.size.to_u32
    write bytes
  end

  def write(value : Bool)
    write value ? Bytes[0x01] : Bytes[0x00]
  end

  def read_bool
    read_byte == 0x01
  end

  def write(value : UInt32 | UInt64) : Nil
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

  def read_int : Int32
    read_bytes Int32, ::IO::ByteFormat::BigEndian
  end

  def read_var_int : UInt32
    result = 0_u32
    shift = 0
    loop do
      b = read_byte
      return result if b.nil?
      result |= ((0x7F & b).to_u32) << shift
      return result if b & 0x80 == 0
      shift += 7
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
end

class Minecraft::IO::Memory < IO::Memory
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

  def read_byte
    buf = Bytes.new 1
    read_fully(buf)
    buf[0]
  end

  def write(slice : Bytes) : Nil
    @io.write @write_cipher.update(slice)
  end

  def flush
    @io.flush
  end
end
