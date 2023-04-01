module Minecraft::NBT
  abstract class Tag
    abstract def tag_type : UInt8

    def self.read(io : IO, tag_type = io.read_byte, &) : Tag # ameba:disable Metrics/CyclomaticComplexity
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
        raise "Unsupported NBT tag type: #{tag_type}"
      end
    end

    def as_i8 : Int8
      raise "Wrong type #{self}" unless self.is_a? ByteTag
      self.value
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

    def as_str : String
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
      tag = read(io, tag_type) { name = StringTag.read(io).value }

      {name, tag}
    end

    def write_named(io : Minecraft::IO, name : String)
      io.write_byte tag_type
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
      raise NotImplementedError.new "#write(io) not implemented for EndTag, please use EndTag.write(io) instead."
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
      new io.read_string io.read_ushort
    end

    def write(io : Minecraft::IO)
      io.write_full value.bytesize.to_u16
      io.print value
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

    def initialize(@value : Hash(String, Tag))
    end

    def self.read(io : IO)
      tags = Hash(String, Tag).new

      loop do
        name = ""
        tag = Tag.read(io) do |tag_type|
          name = if tag_type == 0
                   ""
                 else
                   StringTag.read(io).value
                 end
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

    def [](key)
      value[key]
    end

    def inspect(io)
      io << @value.inspect
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

    def inpsect(io)
      io << @value.inspect
    end
  end

  class LongArrayTag < Tag
    def tag_type : UInt8
      12_u8
    end

    getter values : Array(Int64)

    def initialize(@values : Array(Int64))
    end

    def self.read(io : IO) : LongArrayTag
      length = io.read_int
      values = Array(Int64).new(length)

      length.times do
        values << io.read_long
      end

      new(values)
    end

    def write(io : IO)
      io.write_full values.size.to_i32

      values.each do |val|
        io.write_full val
      end
    end

    def inspect(io)
      io << "NBT[#{values.inspect} : LongArray]"
    end
  end
end
