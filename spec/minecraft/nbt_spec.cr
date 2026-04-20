require "../spec_helper"
require "compress/gzip"

Spectator.describe Minecraft::NBT do
  let(:io) { Minecraft::IO::Memory.new File.read(nbt) }
  let(:io_from_gzip) {
    Minecraft::IO::Memory.new Compress::Gzip::Reader.open(File.open(nbt)) { |gzip|
      gzip.gets_to_end
    }
  }

  describe "hello_world.nbt" do
    let(:nbt) { File.join(__DIR__, "../fixtures/nbt/hello_world.nbt") }

    it "parses the NBT data correctly" do
      name, tag = Minecraft::NBT::Tag.read_named(io)

      expect(name).to eq("hello world")
      expect(tag["name"].value).to eq("Bananrama")
    end

    it "writes the NBT data the same after parsing" do
      name, tag = Minecraft::NBT::Tag.read_named(io)

      actual = Minecraft::IO::Memory.new
      tag.write_named actual, name
      actual.seek 0

      expect(actual.gets_to_end).to eq(File.read(nbt))
    end
  end

  describe "bigtest.nbt" do
    let(:nbt) { File.join(__DIR__, "../fixtures/nbt/bigtest.nbt") }

    it "parses the NBT data correctly" do
      name, tag = Minecraft::NBT::Tag.read_named(io_from_gzip)

      expect(name).to eq("Level")
      expect(tag["nested compound test"]["ham"]["name"].value).to eq("Hampus")
      expect(tag["nested compound test"]["ham"]["value"].value).to eq(0.75)
    end

    it "writes the NBT data the same after parsing" do
      name, tag = Minecraft::NBT::Tag.read_named(io_from_gzip)

      actual = Minecraft::IO::Memory.new
      tag.write_named actual, name

      actual.seek 0
      io_from_gzip.seek 0

      expect(actual.gets_to_end).to eq io_from_gzip.gets_to_end
    end
  end

  describe "level.dat" do
    let(:nbt) { File.join(__DIR__, "../fixtures/nbt/level.dat") }

    it "writes the NBT data the same after parsing" do
      name, tag = Minecraft::NBT::Tag.read_named(io_from_gzip)

      actual = Minecraft::IO::Memory.new
      tag.write_named actual, name

      actual.seek 0
      io_from_gzip.seek 0

      expect(actual.gets_to_end).to eq io_from_gzip.gets_to_end
    end
  end

  describe "playerdata/0b40e79c-9d25-3e6d-b067-1c9d9b164981.dat" do
    let(:nbt) { File.join(__DIR__, "../fixtures/nbt/0b40e79c-9d25-3e6d-b067-1c9d9b164981.dat") }

    it "writes the NBT data the same after parsing" do
      name, tag = Minecraft::NBT::Tag.read_named(io_from_gzip)

      actual = Minecraft::IO::Memory.new
      tag.write_named actual, name

      actual.seek 0
      io_from_gzip.seek 0

      expect(actual.gets_to_end).to eq io_from_gzip.gets_to_end
    end
  end

  describe "Modified UTF-8 StringTag round-trip" do
    def round_trip(sample : String) : String
      buffer = Minecraft::IO::Memory.new
      Minecraft::NBT::StringTag.new(sample).write(buffer)
      buffer.seek 0
      Minecraft::NBT::StringTag.read(buffer).value
    end

    it "round-trips plain ASCII" do
      expect(round_trip("hello")).to eq("hello")
    end

    it "round-trips the empty string" do
      expect(round_trip("")).to eq("")
    end

    it "round-trips an embedded NUL" do
      expect(round_trip("\u0000")).to eq("\u0000")
      expect(round_trip("ab\u0000cd")).to eq("ab\u0000cd")
    end

    it "round-trips a 2-byte codepoint" do
      expect(round_trip("café")).to eq("café")
    end

    it "round-trips a supplementary codepoint via surrogate pair" do
      expect(round_trip("🎮")).to eq("🎮")
      expect(round_trip("a🎮b")).to eq("a🎮b")
    end

    it "encodes NUL as overlong 0xC0 0x80" do
      buffer = Minecraft::IO::Memory.new
      Minecraft::NBT::StringTag.new("\u0000").write(buffer)
      bytes = buffer.to_slice
      # 2-byte big-endian length prefix, then 0xC0 0x80
      expect(bytes[0]).to eq(0_u8)
      expect(bytes[1]).to eq(2_u8)
      expect(bytes[2]).to eq(0xC0_u8)
      expect(bytes[3]).to eq(0x80_u8)
    end

    it "encodes supplementary codepoints as a 6-byte surrogate pair" do
      buffer = Minecraft::IO::Memory.new
      Minecraft::NBT::StringTag.new("🎮").write(buffer)
      bytes = buffer.to_slice
      # U+1F3AE → surrogate pair U+D83C U+DFAE, each encoded as 3 bytes
      expect(bytes[0]).to eq(0_u8)
      expect(bytes[1]).to eq(6_u8)
      expect(bytes[2]).to eq(0xED_u8)
      expect(bytes[3]).to eq(0xA0_u8)
      expect(bytes[4]).to eq(0xBC_u8)
      expect(bytes[5]).to eq(0xED_u8)
      expect(bytes[6]).to eq(0xBE_u8)
      expect(bytes[7]).to eq(0xAE_u8)
    end
  end

  describe "ListTag type validation" do
    it "rejects a list with type=END and length>0" do
      buffer = Minecraft::IO::Memory.new
      buffer.write_byte 0_u8  # type=END
      buffer.write_full 3_i32 # length=3
      buffer.seek 0
      expect { Minecraft::NBT::ListTag.read(buffer) }.to raise_error(Minecraft::NBT::DecodeError)
    end

    it "accepts a list with type=END and length=0" do
      buffer = Minecraft::IO::Memory.new
      buffer.write_byte 0_u8
      buffer.write_full 0_i32
      buffer.seek 0
      list = Minecraft::NBT::ListTag.read(buffer)
      expect(list.value).to be_empty
    end
  end
end
