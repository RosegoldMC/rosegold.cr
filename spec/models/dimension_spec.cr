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

  describe ".from_registry" do
    it "uses min_y/height from the server-supplied dimension_type registry" do
      # Build the unnamed CompoundTag NBT a vanilla server would send for a
      # custom dimension_type entry. RegistryData captures the bytes that
      # `Minecraft::NBT::Tag.read` consumed, i.e. tag_type byte + payload.
      compound = Minecraft::NBT::CompoundTag.new({
        "min_y"  => Minecraft::NBT::IntTag.new(-32_i32).as(Minecraft::NBT::Tag),
        "height" => Minecraft::NBT::IntTag.new(512_i32).as(Minecraft::NBT::Tag),
      })
      nbt_buf = Minecraft::IO::Memory.new
      nbt_buf.write_byte(compound.tag_type)
      compound.write(nbt_buf)
      entry_bytes = nbt_buf.to_slice

      registries = Hash(String, Rosegold::Clientbound::RegistryData).new
      registries["minecraft:dimension_type"] = Rosegold::Clientbound::RegistryData.new(
        "minecraft:dimension_type",
        [{id: "minecraft:custom", data: entry_bytes.dup.as(Slice(UInt8) | Nil)}]
      )

      dim = Rosegold::Dimension.from_registry("minecraft:custom", 0_u32, registries)

      expect(dim.name).to eq("minecraft:custom")
      expect(dim.min_y).to eq(-32)
      expect(dim.world_height).to eq(512)
      expect(dim.dimension_type).to eq(0_u32)
    end

    it "falls back to vanilla defaults when the registry is empty" do
      registries = Hash(String, Rosegold::Clientbound::RegistryData).new
      dim = Rosegold::Dimension.from_registry("minecraft:the_nether", 7_u32, registries)

      expect(dim.world_height).to eq(256)
      expect(dim.min_y).to eq(0)
      expect(dim.dimension_type).to eq(7_u32)
    end
  end
end
