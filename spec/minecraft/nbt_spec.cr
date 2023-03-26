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
end
