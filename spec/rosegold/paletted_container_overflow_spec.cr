require "../spec_helper"

Spectator.describe Rosegold::PalettedContainer do
  describe "arithmetic overflow protection" do
    it "handles real chunk data from CivMC that causes overflow" do
      # Test data captured from CivMC server that causes bits_per_entry=115 overflow
      chunk_data = File.read("spec/fixtures/chunk_data/civmc_overflow_83_312.bin")

      dimension = Rosegold::Dimension.new
      source = Minecraft::IO::Memory.new(chunk_data)

      # This should handle the overflow gracefully instead of crashing
      expect do
        Rosegold::Chunk.new 83, 312, source, dimension
      end.not_to raise_error(OverflowError, /Arithmetic overflow/)
    end
  end
end
