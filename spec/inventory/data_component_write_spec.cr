require "../spec_helper"

# Regression guards for wire-encoding asymmetries between read and write.
# These components use `ByteBufCodecs.INT` on the wire (raw big-endian Int32),
# not VarInt. An earlier version of write() dispatched to the polymorphic
# `io.write(Int32)` overload which emits VarInt — breaking vanilla decode.
Spectator.describe "DataComponent write wire sizes" do
  describe Rosegold::DataComponents::DyedColor do
    it "writes color as 4 big-endian bytes (not VarInt)" do
      # 0x12345678 in VarInt would be 4 bytes but with high-bit continuation
      # markers; as raw BE it's exactly 12 34 56 78.
      io = Minecraft::IO::Memory.new
      Rosegold::DataComponents::DyedColor.new(0x12345678).write(io)
      expect(io.to_slice.hexstring).to eq("12345678")
    end

    it "round-trips through read" do
      io = Minecraft::IO::Memory.new
      Rosegold::DataComponents::DyedColor.new(-1).write(io)
      read_io = Minecraft::IO::Memory.new(io.to_slice)
      expect(Rosegold::DataComponents::DyedColor.read(read_io).color).to eq(-1)
    end
  end

  describe Rosegold::DataComponents::MapColor do
    it "writes color as 4 big-endian bytes (not VarInt)" do
      io = Minecraft::IO::Memory.new
      Rosegold::DataComponents::MapColor.new(0x12345678).write(io)
      expect(io.to_slice.hexstring).to eq("12345678")
    end
  end
end
