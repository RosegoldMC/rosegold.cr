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
  end

  describe "bigtest.nbt" do # this is a gzip'd file
    let(:nbt) { File.join(__DIR__, "../fixtures/nbt/bigtest.nbt") }

    it "parses the NBT data correctly" do
      name, tag = Minecraft::NBT::Tag.read_named(io_from_gzip)

      expect(name).to eq("Level")
      expect(tag["nested compound test"]["ham"]["name"].value).to eq("Hampus")
      expect(tag["nested compound test"]["ham"]["value"].value).to eq(0.75)
    end
  end
end
