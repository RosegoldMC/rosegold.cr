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

  # Regression: brewery infinite potions send duration -1 (VarInt 0xFFFFFFFF) and
  # alpha custom colors set the Int32 high bit. Checked casts (.to_i32 / .to_u32)
  # threw OverflowError, crashing SetContainerContent parsing on CivMC.
  describe Rosegold::DataComponents::PotionContents do
    it "reads duration -1 (infinite potion) without overflow" do
      # has_potion_id=0, has_custom_color=0, effects=1,
      # effect: type_id=1, amplifier=0, duration=VarInt(-1), ambient=0,
      # show_particles=1, show_icon=1, has_hidden=0; has_custom_name=0
      io = Minecraft::IO::Memory.new("0000010100ffffffff0f0001010000".hexbytes)
      pc = Rosegold::DataComponents::PotionContents.read(io)
      expect(pc.custom_effects[0].duration).to eq(-1)
    end

    it "round-trips an infinite-duration effect byte-identically" do
      bytes = "0000010100ffffffff0f0001010000".hexbytes
      pc = Rosegold::DataComponents::PotionContents.read(Minecraft::IO::Memory.new(bytes))
      buf = Minecraft::IO::Memory.new
      pc.write(buf)
      expect(buf.to_slice.hexstring).to eq(bytes.hexstring)
    end

    it "reads a custom_color with the alpha high bit set without overflow" do
      # has_potion_id=0, has_custom_color=1, color=0xFF0000FF, effects=0, has_name=0
      io = Minecraft::IO::Memory.new("0001ff0000ff0000".hexbytes)
      pc = Rosegold::DataComponents::PotionContents.read(io)
      expect(pc.custom_color).to eq(0xFF0000FF_u32)
    end
  end
end
