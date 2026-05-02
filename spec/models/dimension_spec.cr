require "../spec_helper"

Spectator.describe Rosegold::Dimension do
  after_each { Rosegold::Client.reset_protocol_version! }

  describe ".new_nether" do
    # Vanilla `the_nether` dimension type uses height=256 (16 sections per chunk).
    # `logical_height` is 128 (build limit), but section data on the wire fills
    # the full 256-block range. Mismatching this corrupts spectator chunk
    # forwarding and breaks vanilla clients with an IndexOutOfBoundsException.
    it "matches vanilla Nether height (16 sections)" do
      dim = Rosegold::Dimension.new_nether
      expect(dim.world_height).to eq(256)
      expect(dim.world_height >> 4).to eq(16)
    end
  end

  describe "Chunk parsing" do
    it "consumes all section data for a Nether chunk" do
      Rosegold::Client.protocol_version = 772_u32

      buf = Minecraft::IO::Memory.new
      16.times { Rosegold::Section.empty.write(buf) }
      section_bytes = buf.to_slice

      io = Minecraft::IO::Memory.new(section_bytes)
      chunk = Rosegold::Chunk.new(0, 0, io, Rosegold::Dimension.new_nether)

      expect(chunk.sections.size).to eq(16)
      expect(io.pos).to eq(section_bytes.size)
      expect(chunk.data.size).to eq(section_bytes.size)
    end
  end
end
