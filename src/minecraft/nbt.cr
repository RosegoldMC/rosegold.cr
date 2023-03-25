module Minecraft::NBT
  abstract class Tag
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

    def self.read(io : IO, tag_type = io.read_byte) : Tag
      read(io, tag_type) { }
    end

    alias NamedTag = {String, Tag}

    def self.read_named(io : IO, tag_type = io.read_byte) : NamedTag
      name = ""
      tag = read(io, tag_type) { name = StringTag.read(io).value }

      {name, tag}
    end

    def [](value)
      raise NotImplementedError.new "#[] not implemented for #{self.class}"
    end

    def value
      raise NotImplementedError.new "#value not implemented for #{self.class}"
    end
  end

  class EndTag < Tag
    def self.read(io)
      new
    end
  end

  class ByteTag < Tag
    getter value : UInt8

    def initialize(@value : UInt8)
    end

    def self.read(io : IO) : ByteTag
      new io.read_byte
    end

    def inspect(io)
      io << "NBT[#{value} : Byte]"
    end
  end

  class ShortTag < Tag
    getter value : Int16

    def initialize(@value : Int16)
    end

    def self.read(io : IO) : ShortTag
      new io.read_short
    end

    def inspect(io)
      io << "NBT[#{value} : Short]"
    end
  end

  class IntTag < Tag
    getter value : Int32

    def initialize(@value : Int32)
    end

    def self.read(io : IO) : IntTag
      new io.read_int
    end

    def inspect(io)
      io << "NBT[#{value} : Int]"
    end
  end

  class LongTag < Tag
    getter value : Int64

    def initialize(@value : Int64)
    end

    def self.read(io : IO) : LongTag
      new io.read_long
    end

    def inspect(io)
      io << "NBT[#{value} : Long]"
    end
  end

  class FloatTag < Tag
    getter value : Float32

    def initialize(@value : Float32)
    end

    def self.read(io : IO) : FloatTag
      new io.read_float
    end

    def inspect(io)
      io << "NBT[#{value} : Float]"
    end
  end

  class DoubleTag < Tag
    getter value : Float64

    def initialize(@value : Float64)
    end

    def self.read(io : IO) : DoubleTag
      new io.read_double
    end

    def inspect(io)
      io << "NBT[#{value} : Double]"
    end
  end

  class ByteArrayTag < Tag
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

    def inspect(io)
      io << "NBT[#{value.inspect} : ByteArray]"
    end
  end

  class StringTag < Tag
    getter value : String

    def initialize(@value : String)
    end

    def self.read(io : IO) : StringTag
      new io.read_string io.read_ushort
    end

    def inspect(io)
      io << "NBT[\"#{value}\" : String]"
    end
  end

  class CompoundTag < Tag
    getter tags : Hash(String, Tag)

    def initialize(@tags : Hash(String, Tag))
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

    def [](key)
      tags[key]
    end

    def inspect(io)
      io << @tags.inspect
    end
  end

  class IntArrayTag < Tag
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

    def inspect(io)
      io << "NBT[#{value.inspect} : IntArray]"
    end
  end

  class ListTag < Tag
    getter tags : Array(Tag)

    def initialize(@tags : Array(Tag))
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

    def inpsect(io)
      io << @tags.inspect
    end
  end

  class LongArrayTag < Tag
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

    def inspect(io)
      io << "NBT[#{values.inspect} : LongArray]"
    end
  end
end
