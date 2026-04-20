module Minecraft::NBT
  class DecodeError < Exception
  end

  # Minecraft NBT strings use Java's "Modified UTF-8": supplementary codepoints
  # are written as a UTF-16 surrogate pair (each surrogate encoded in 3 bytes),
  # and NUL is written as the two-byte overlong 0xC0 0x80. Plain UTF-8 corrupts
  # such strings, so we encode/decode explicitly.
  def self.modified_utf8_encode(s : String) : Bytes
    buffer = ::IO::Memory.new

    s.each_char do |char|
      c = char.ord

      if c == 0
        buffer.write_byte 0xC0_u8
        buffer.write_byte 0x80_u8
      elsif c <= 0x7F
        buffer.write_byte c.to_u8
      elsif c <= 0x7FF
        buffer.write_byte (0xC0 | (c >> 6)).to_u8
        buffer.write_byte (0x80 | (c & 0x3F)).to_u8
      elsif c <= 0xFFFF
        buffer.write_byte (0xE0 | (c >> 12)).to_u8
        buffer.write_byte (0x80 | ((c >> 6) & 0x3F)).to_u8
        buffer.write_byte (0x80 | (c & 0x3F)).to_u8
      else
        adjusted = c - 0x10000
        high = 0xD800 | (adjusted >> 10)
        low = 0xDC00 | (adjusted & 0x3FF)

        buffer.write_byte (0xE0 | (high >> 12)).to_u8
        buffer.write_byte (0x80 | ((high >> 6) & 0x3F)).to_u8
        buffer.write_byte (0x80 | (high & 0x3F)).to_u8

        buffer.write_byte (0xE0 | (low >> 12)).to_u8
        buffer.write_byte (0x80 | ((low >> 6) & 0x3F)).to_u8
        buffer.write_byte (0x80 | (low & 0x3F)).to_u8
      end
    end

    buffer.to_slice
  end

  def self.modified_utf8_decode(bytes : Bytes) : String
    code_units = Array(UInt16).new
    i = 0
    while i < bytes.size
      b0 = bytes[i]
      if b0 < 0x80_u8
        code_units << b0.to_u16
        i += 1
      elsif (b0 & 0xE0_u8) == 0xC0_u8
        raise DecodeError.new("Invalid Modified UTF-8 byte") if i + 1 >= bytes.size
        b1 = bytes[i + 1]
        cu = ((b0 & 0x1F_u8).to_u16 << 6) | (b1 & 0x3F_u8).to_u16
        code_units << cu
        i += 2
      elsif (b0 & 0xF0_u8) == 0xE0_u8
        raise DecodeError.new("Invalid Modified UTF-8 byte") if i + 2 >= bytes.size
        b1 = bytes[i + 1]
        b2 = bytes[i + 2]
        cu = ((b0 & 0x0F_u8).to_u16 << 12) | ((b1 & 0x3F_u8).to_u16 << 6) | (b2 & 0x3F_u8).to_u16
        code_units << cu
        i += 3
      else
        raise DecodeError.new("Invalid Modified UTF-8 byte")
      end
    end

    String.build do |io|
      j = 0
      while j < code_units.size
        cu = code_units[j]
        if cu >= 0xD800_u16 && cu <= 0xDBFF_u16 &&
           j + 1 < code_units.size &&
           code_units[j + 1] >= 0xDC00_u16 && code_units[j + 1] <= 0xDFFF_u16
          high = cu.to_i32
          low = code_units[j + 1].to_i32
          codepoint = ((high - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          io << codepoint.chr
          j += 2
        else
          io << cu.to_i32.chr
          j += 1
        end
      end
    end
  end

  abstract class Tag
    abstract def tag_type : UInt8

    def self.read(io : IO, tag_type = io.read_byte, &) : Tag
      yield tag_type

      case tag_type
      when 0
        EndTag.read io
      when 1
        ByteTag.read io
      when 2
        ShortTag.read io
      when 3
        IntTag.read io
      when 4
        LongTag.read io
      when 5
        FloatTag.read io
      when 6
        DoubleTag.read io
      when 7
        ByteArrayTag.read io
      when 8
        StringTag.read io
      when 9
        ListTag.read io
      when 10
        CompoundTag.read io
      when 11
        IntArrayTag.read io
      when 12
        LongArrayTag.read io
      else
        raise DecodeError.new("Unsupported NBT tag type: #{tag_type}")
      end
    end

    def as_i : Int8 | Int16 | Int32 | Int64 | UInt8
      case self
      when ByteTag
        self.value
      when ShortTag
        self.value
      when IntTag
        self.value
      when LongTag
        self.value
      else
        raise "Wrong type #{self}"
      end
    end

    def as_i8 : Int8
      raise "Wrong type #{self}" unless self.is_a? ByteTag
      self.value.to_i8!
    end

    def as_i16 : Int16
      raise "Wrong type #{self}" unless self.is_a? ShortTag
      self.value
    end

    def as_i32 : Int32
      raise "Wrong type #{self}" unless self.is_a? IntTag
      self.value
    end

    def as_i64 : Int64
      raise "Wrong type #{self}" unless self.is_a? LongTag
      self.value
    end

    def as_f32 : Float32
      raise "Wrong type #{self}" unless self.is_a? FloatTag
      self.value
    end

    def as_f64 : Float64
      raise "Wrong type #{self}" unless self.is_a? DoubleTag
      self.value
    end

    def as_byte_array : Array(Int8)
      raise "Wrong type #{self}" unless self.is_a? ByteArrayTag
      self.value
    end

    def as_s : String
      raise "Wrong type #{self}" unless self.is_a? StringTag
      self.value
    end

    def as_list : Array(Tag)
      raise "Wrong type #{self}" unless self.is_a? ListTag
      self.value
    end

    def as_compound : Hash(String, Tag)
      raise "Wrong type #{self}" unless self.is_a? CompoundTag
      self.value
    end

    def as_i32_array : Array(Int32)
      raise "Wrong type #{self}" unless self.is_a? IntArrayTag
      self.value
    end

    def as_i64_array : Array(Int64)
      raise "Wrong type #{self}" unless self.is_a? LongArrayTag
      self.value
    end

    def self.read(io : IO, tag_type = io.read_byte) : Tag
      read(io, tag_type) { }
    end

    alias NamedTag = {String, Tag}

    def self.read_named(io : IO, tag_type = io.read_byte) : NamedTag
      name = ""
      tag = Tag.read(io, tag_type) do
        name = StringTag.read(io).value unless tag_type == 0
      end

      {name, tag}
    end

    def write_named(io : Minecraft::IO, name : String = "")
      io.write_byte tag_type
      return if self.is_a? EndTag
      StringTag.new(name).write io
      write io
    end

    def [](value)
      raise NotImplementedError.new "#[] not implemented for #{self.class}"
    end

    def value
      raise NotImplementedError.new "#value not implemented for #{self.class}"
    end
  end

  class EndTag < Tag
    def tag_type : UInt8
      0_u8
    end

    def self.read(io)
      new
    end

    def self.write(io)
      io.write_byte 0
    end

    def write(io)
      EndTag.write io
    end
  end

  class ByteTag < Tag
    getter value : UInt8

    def tag_type : UInt8
      1_u8
    end

    def initialize(@value : UInt8)
    end

    def self.read(io : IO) : ByteTag
      new io.read_byte
    end

    def write(io)
      io.write_byte value
    end

    def inspect(io)
      io << "NBT[#{value} : Byte]"
    end
  end

  class ShortTag < Tag
    def tag_type : UInt8
      2_u8
    end

    getter value : Int16

    def initialize(@value : Int16)
    end

    def self.read(io : IO) : ShortTag
      new io.read_short
    end

    def write(io : IO)
      io.write_full value
    end

    def inspect(io)
      io << "NBT[#{value} : Short]"
    end
  end

  class IntTag < Tag
    def tag_type : UInt8
      3_u8
    end

    getter value : Int32

    def initialize(@value : Int32)
    end

    def self.read(io : IO) : IntTag
      new io.read_int
    end

    def write(io : IO)
      io.write_full value
    end

    def inspect(io)
      io << "NBT[#{value} : Int]"
    end
  end

  class LongTag < Tag
    def tag_type : UInt8
      4_u8
    end

    getter value : Int64

    def initialize(@value : Int64)
    end

    def self.read(io : IO) : LongTag
      new io.read_long
    end

    def write(io : IO)
      io.write_full value
    end

    def inspect(io)
      io << "NBT[#{value} : Long]"
    end
  end

  class FloatTag < Tag
    def tag_type : UInt8
      5_u8
    end

    getter value : Float32

    def initialize(@value : Float32)
    end

    def self.read(io : IO) : FloatTag
      new io.read_float
    end

    def write(io : IO)
      io.write_full value
    end

    def inspect(io)
      io << "NBT[#{value} : Float]"
    end
  end

  class DoubleTag < Tag
    def tag_type : UInt8
      6_u8
    end

    getter value : Float64

    def initialize(@value : Float64)
    end

    def self.read(io : IO) : DoubleTag
      new io.read_double
    end

    def write(io : IO)
      io.write_full value
    end

    def inspect(io)
      io << "NBT[#{value} : Double]"
    end
  end

  class ByteArrayTag < Tag
    def tag_type : UInt8
      7_u8
    end

    getter value : Array(Int8)

    def initialize(@value : Array(Int8))
    end

    def self.read(io : IO) : ByteArrayTag
      length = io.read_int
      value = Array(Int8).new(length)

      length.times do
        value << io.read_byte.to_i8
      end

      new(value)
    end

    def write(io : IO)
      io.write_full value.size.to_i32
      value.each do |val|
        io.write_byte val.to_u8
      end
    end

    def inspect(io)
      io << "NBT[#{value.inspect} : ByteArray]"
    end
  end

  class StringTag < Tag
    def tag_type : UInt8
      8_u8
    end

    getter value : String

    def initialize(@value : String)
    end

    def self.read(io : Minecraft::IO) : StringTag
      length = io.read_ushort
      buffer = Bytes.new(length)
      io.read_fully(buffer) if length > 0
      new Minecraft::NBT.modified_utf8_decode(buffer)
    end

    def write(io : Minecraft::IO)
      bytes = Minecraft::NBT.modified_utf8_encode(value)
      io.write_full bytes.size.to_u16
      io.write bytes
    end

    def inspect(io)
      io << "NBT[\"#{value}\" : String]"
    end
  end

  class CompoundTag < Tag
    def tag_type : UInt8
      10_u8
    end

    getter value : Hash(String, Tag)

    def initialize(@value : Hash(String, Tag)); end

    def self.new
      self.new({} of String => Tag)
    end

    def self.read(io : IO)
      tags = Hash(String, Tag).new

      loop do
        name = ""
        tag = Tag.read(io) do |tag_type|
          name = StringTag.read(io).value unless tag_type == 0
        end

        if tag.is_a? EndTag
          return new(tags)
        end

        tags[name] = tag
      end
    end

    def write(io)
      value.each do |name, tag|
        tag.write_named(io, name)
      end
      EndTag.write(io)
    end

    delegate :[], :[]=, :[]?, to: value

    def inspect(io)
      io << @value.inspect
    end

    def ==(other)
      other.is_a?(CompoundTag) && self.value == other.value
    end
  end

  class IntArrayTag < Tag
    def tag_type : UInt8
      11_u8
    end

    getter value : Array(Int32)

    def initialize(@value : Array(Int32))
    end

    def self.read(io : IO) : IntArrayTag
      length = io.read_int
      value = Array(Int32).new(length)

      length.times do
        value << io.read_int
      end

      new(value)
    end

    def write(io : IO)
      io.write_full value.size.to_i32

      value.each do |val|
        io.write_full val
      end
    end

    def inspect(io)
      io << "NBT[#{value.inspect} : IntArray]"
    end
  end

  class ListTag < Tag
    def tag_type : UInt8
      9_u8
    end

    getter value : Array(Tag)

    def initialize(@value : Array(Tag))
    end

    def self.read(io : IO) : ListTag
      list_tag_type = io.read_byte
      list_length = io.read_int

      if list_tag_type == 0_u8 && list_length > 0
        raise DecodeError.new("ListTag with type=END and length=#{list_length}")
      end

      tags = Array(Tag).new(list_length)

      list_length.times do
        tag = Tag.read io, list_tag_type
        tags << tag
      end

      new(tags)
    end

    def write(io : IO)
      if value.empty?
        io.write_byte 0_u8
        io.write_full 0_i32
        return
      end

      io.write_byte value.first.tag_type
      io.write_full value.size.to_i32

      value.each do |tag|
        tag.write io
      end
    end

    def inspect(io)
      io << @value.inspect
    end
  end

  class LongArrayTag < Tag
    def tag_type : UInt8
      12_u8
    end

    getter value : Array(Int64)

    def initialize(@value : Array(Int64))
    end

    def self.read(io : IO) : LongArrayTag
      length = io.read_int
      value = Array(Int64).new(length)

      length.times do
        value << io.read_long
      end

      new(value)
    end

    def write(io : IO)
      io.write_full value.size.to_i32

      value.each do |val|
        io.write_full val
      end
    end

    def inspect(io)
      io << "NBT[#{value.inspect} : LongArray]"
    end

    def ==(other)
      other.is_a?(LongArrayTag) && self.value == other.value
    end
  end
end
