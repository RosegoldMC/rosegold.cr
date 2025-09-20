require "../spec_helper"
require "compress/gzip"

Spectator.describe "NBT Tag Serialization" do
  describe "ByteTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::ByteTag.new(42_u8)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ByteTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "ShortTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::ShortTag.new(-1337_i16)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ShortTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "IntTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::IntTag.new(2147483647_i32)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::IntTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "LongTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::LongTag.new(-9223372036854775808_i64)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::LongTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "FloatTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::FloatTag.new(3.14159_f32)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::FloatTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "DoubleTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::DoubleTag.new(2.718281828459045_f64)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::DoubleTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "ByteArrayTag" do
    it "preserves value through write-read cycle" do
      test_data = [100_i8, 0_i8, 127_i8, 42_i8, 50_i8]
      original = Minecraft::NBT::ByteArrayTag.new(test_data)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ByteArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "handles empty arrays" do
      original = Minecraft::NBT::ByteArrayTag.new([] of Int8)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ByteArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "StringTag" do
    it "preserves value through write-read cycle" do
      original = Minecraft::NBT::StringTag.new("Hello, NBT World!")
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::StringTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "handles empty strings" do
      original = Minecraft::NBT::StringTag.new("")
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::StringTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "handles unicode strings" do
      original = Minecraft::NBT::StringTag.new("🚀 Crystal NBT Test 日本語 🎮")
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::StringTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "IntArrayTag" do
    it "preserves value through write-read cycle" do
      test_data = [-2147483648_i32, 0_i32, 2147483647_i32, 42_i32, -1_i32]
      original = Minecraft::NBT::IntArrayTag.new(test_data)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::IntArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "handles empty arrays" do
      original = Minecraft::NBT::IntArrayTag.new([] of Int32)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::IntArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "LongArrayTag" do
    it "preserves value through write-read cycle" do
      test_data = [-9223372036854775808_i64, 0_i64, 9223372036854775807_i64, 42_i64, -1_i64]
      original = Minecraft::NBT::LongArrayTag.new(test_data)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::LongArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "handles empty arrays" do
      original = Minecraft::NBT::LongArrayTag.new([] of Int64)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::LongArrayTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "ListTag" do
    it "preserves homogeneous list through write-read cycle" do
      int_tags = [
        Minecraft::NBT::IntTag.new(1_i32),
        Minecraft::NBT::IntTag.new(2_i32),
        Minecraft::NBT::IntTag.new(3_i32),
      ]
      original = Minecraft::NBT::ListTag.new(int_tags.map(&.as(Minecraft::NBT::Tag)))
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ListTag.read(io)
      expect(read_back.value.size).to eq(original.value.size)

      read_back.value.each_with_index do |tag, i|
        expect(tag.as(Minecraft::NBT::IntTag).value).to eq(int_tags[i].value)
      end
    end

    it "handles empty lists" do
      original = Minecraft::NBT::ListTag.new([] of Minecraft::NBT::Tag)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::ListTag.read(io)
      expect(read_back.value).to eq(original.value)
    end
  end

  describe "CompoundTag" do
    it "preserves complex nested structure through write-read cycle" do
      compound_data = {
        "byte_value"      => Minecraft::NBT::ByteTag.new(42_u8).as(Minecraft::NBT::Tag),
        "string_value"    => Minecraft::NBT::StringTag.new("test").as(Minecraft::NBT::Tag),
        "int_array"       => Minecraft::NBT::IntArrayTag.new([1_i32, 2_i32, 3_i32]).as(Minecraft::NBT::Tag),
        "nested_compound" => Minecraft::NBT::CompoundTag.new({
          "inner_float"  => Minecraft::NBT::FloatTag.new(1.5_f32).as(Minecraft::NBT::Tag),
          "inner_string" => Minecraft::NBT::StringTag.new("nested").as(Minecraft::NBT::Tag),
        } of String => Minecraft::NBT::Tag).as(Minecraft::NBT::Tag),
      }

      original = Minecraft::NBT::CompoundTag.new(compound_data)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::CompoundTag.read(io)

      # Check top-level values
      expect(read_back["byte_value"].as(Minecraft::NBT::ByteTag).value).to eq(42_u8)
      expect(read_back["string_value"].as(Minecraft::NBT::StringTag).value).to eq("test")
      expect(read_back["int_array"].as(Minecraft::NBT::IntArrayTag).value).to eq([1_i32, 2_i32, 3_i32])

      # Check nested compound
      nested = read_back["nested_compound"].as(Minecraft::NBT::CompoundTag)
      expect(nested["inner_float"].as(Minecraft::NBT::FloatTag).value).to eq(1.5_f32)
      expect(nested["inner_string"].as(Minecraft::NBT::StringTag).value).to eq("nested")
    end

    it "handles empty compounds" do
      original = Minecraft::NBT::CompoundTag.new
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::CompoundTag.read(io)
      expect(read_back.value).to eq(original.value)
    end

    it "preserves simple compound values" do
      compound_data = {
        "test_key" => Minecraft::NBT::StringTag.new("test_value").as(Minecraft::NBT::Tag),
      }

      original = Minecraft::NBT::CompoundTag.new(compound_data)
      io = Minecraft::IO::Memory.new

      original.write(io)
      io.rewind

      read_back = Minecraft::NBT::CompoundTag.read(io)
      expect(read_back.value.size).to eq(original.value.size)
      expect(read_back["test_key"].as(Minecraft::NBT::StringTag).value).to eq("test_value")
    end
  end

  describe "Real-world NBT file: bigtest.nbt" do
    it "preserves content through write-read cycle" do
      nbt_file_path = File.join(__DIR__, "../fixtures/nbt/bigtest.nbt")

      # Read the gzipped NBT file
      original_bytes = Compress::Gzip::Reader.open(File.open(nbt_file_path)) do |gzip|
        gzip.gets_to_end.to_slice
      end

      # Parse the original NBT data
      original_io = Minecraft::IO::Memory.new(original_bytes)
      original_name, original_tag = Minecraft::NBT::Tag.read_named(original_io)

      # Write it back to a buffer
      write_io = Minecraft::IO::Memory.new
      original_tag.write_named(write_io, original_name)
      write_io.seek(0)

      # Read it back again
      read_name, read_tag = Minecraft::NBT::Tag.read_named(write_io)

      # Verify the names match
      expect(read_name).to eq(original_name)

      # Verify specific nested values match (from the bigtest.nbt structure)
      expect(read_tag["nested compound test"]["ham"]["name"].as_s).to eq("Hampus")
      expect(read_tag["nested compound test"]["ham"]["value"].as_f32).to eq(0.75_f32)
      expect(read_tag["intTest"].as_i32).to eq(2147483647_i32)
      expect(read_tag["byteTest"].as_i8).to eq(127_i8)
      expect(read_tag["stringTest"].as_s).to eq("HELLO WORLD THIS IS A TEST STRING ÅÄÖ!")
    end
  end
end
