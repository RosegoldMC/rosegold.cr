require "../spec_helper"

Spectator.describe Minecraft::IO do
  describe "VarInt write/read round-trip" do
    it "encodes and decodes 0" do
      io = Minecraft::IO::Memory.new
      io.write 0_u32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 0_u32
    end

    it "encodes and decodes 1" do
      io = Minecraft::IO::Memory.new
      io.write 1_u32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 1_u32
    end

    it "encodes and decodes 127" do
      io = Minecraft::IO::Memory.new
      io.write 127_u32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 127_u32
    end

    it "encodes and decodes 128" do
      io = Minecraft::IO::Memory.new
      io.write 128_u32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 128_u32
    end

    it "encodes and decodes max UInt32" do
      io = Minecraft::IO::Memory.new
      io.write UInt32::MAX
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq UInt32::MAX
    end

    it "encodes Int32 -1 as two's complement (0xFFFFFFFF)" do
      io = Minecraft::IO::Memory.new
      io.write -1_i32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 0xFFFFFFFF_u32
    end

    it "encodes Int32 -1 which reads back as -1 via to_i32!" do
      io = Minecraft::IO::Memory.new
      io.write -1_i32
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int.to_i32!).to eq -1_i32
    end

    it "encodes Int16 -1 as two's complement (0xFFFF)" do
      io = Minecraft::IO::Memory.new
      io.write -1_i16
      result = Minecraft::IO::Memory.new(io.to_slice)
      expect(result.read_var_int).to eq 0xFFFF_u32
    end
  end
end
