require "../spec_helper"

# Parse-completeness fixes for entity-variant and holder components (issue #338):
#   M2 - ten variant components are bare VarInt on the wire, not Holder.
#   M1 - 775+ dropped the leading EitherHolder bool for damage_type and the
#        Instrument / ProvidesTrimMaterial / JukeboxPlayable raw readers.
#   M3 - painting/variant is an inline Holder<PaintingVariant>, not a plain Holder.
Spectator.describe "DataComponent parse fixes" do
  M2_VARINT_COMPONENTS = %w[
    wolf/variant wolf/sound_variant
    pig/variant pig/sound_variant
    cow/variant cow/sound_variant
    chicken/sound_variant frog/variant
    cat/variant cat/sound_variant
  ]

  describe "M2 entity-variant components read as bare VarInt" do
    sample(M2_VARINT_COMPONENTS) do |name|
      it "#{name} dispatches to VarIntComponent and round-trips" do
        buffer = Minecraft::IO::Memory.new
        buffer.write 7_u32
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponent.create_component_by_name(name, 0_u32, io)

        expect(component).to be_a(Rosegold::DataComponents::VarIntComponent)
        expect(component.as(Rosegold::DataComponents::VarIntComponent).value).to eq(7_u32)

        sink = Minecraft::IO::Memory.new
        component.write(sink)
        expect(sink.to_slice.hexstring).to eq("07")
      end
    end
  end

  describe "M1 damage_type gate" do
    context "protocol 774 (EitherHolder, leading bool present)" do
      before_each { Rosegold::Client.protocol_version = 774_u32 }
      after_each { Rosegold::Client.reset_protocol_version! }

      it "reads the bool then the holder" do
        buffer = Minecraft::IO::Memory.new
        buffer.write true
        buffer.write 3_u32
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponent.create_component_by_name("damage_type", 0_u32, io)

        expect(component).to be_a(Rosegold::DataComponents::EitherHolderComponent)
        expect(component.as(Rosegold::DataComponents::EitherHolderComponent).holder_id).to eq(3_u32)
      end
    end

    context "protocol 775 (bare VarInt, no leading bool)" do
      before_each { Rosegold::Client.protocol_version = 775_u32 }
      after_each { Rosegold::Client.reset_protocol_version! }

      it "reads a bare VarInt" do
        buffer = Minecraft::IO::Memory.new
        buffer.write 3_u32
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponent.create_component_by_name("damage_type", 0_u32, io)

        expect(component).to be_a(Rosegold::DataComponents::VarIntComponent)
        expect(component.as(Rosegold::DataComponents::VarIntComponent).value).to eq(3_u32)
      end
    end
  end

  describe "M1 raw-capture holder readers skip the 775+ bool" do
    # Registry-ref holder (non-zero id) so the reader stops right after the id,
    # leaving the trailing sentinel byte untouched — proving exact byte consumption.
    context "protocol 774 (leading bool present)" do
      before_each { Rosegold::Client.protocol_version = 774_u32 }
      after_each { Rosegold::Client.reset_protocol_version! }

      it "Instrument consumes bool + holder id" do
        buffer = Minecraft::IO::Memory.new
        buffer.write true
        buffer.write 5_u32
        buffer.write_byte 0x7F_u8
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponents::Instrument.read(io)

        expect(component.raw_bytes.hexstring).to eq("0105")
        expect(io.read_byte).to eq(0x7F)
      end
    end

    context "protocol 775 (no leading bool)" do
      before_each { Rosegold::Client.protocol_version = 775_u32 }
      after_each { Rosegold::Client.reset_protocol_version! }

      it "Instrument consumes only the holder id" do
        buffer = Minecraft::IO::Memory.new
        buffer.write 5_u32
        buffer.write_byte 0x7F_u8
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponents::Instrument.read(io)

        expect(component.raw_bytes.hexstring).to eq("05")
        expect(io.read_byte).to eq(0x7F)
      end

      it "ProvidesTrimMaterial consumes only the holder id" do
        buffer = Minecraft::IO::Memory.new
        buffer.write 5_u32
        buffer.write_byte 0x7F_u8
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponents::ProvidesTrimMaterial.read(io)

        expect(component.raw_bytes.hexstring).to eq("05")
        expect(io.read_byte).to eq(0x7F)
      end

      it "JukeboxPlayable consumes only the holder id" do
        buffer = Minecraft::IO::Memory.new
        buffer.write 5_u32
        buffer.write_byte 0x7F_u8
        io = Minecraft::IO::Memory.new(buffer.to_slice)

        component = Rosegold::DataComponents::JukeboxPlayable.read(io)

        expect(component.raw_bytes.hexstring).to eq("05")
        expect(io.read_byte).to eq(0x7F)
      end
    end
  end

  describe "M3 painting/variant inline reader" do
    it "dispatches to PaintingVariant" do
      buffer = Minecraft::IO::Memory.new
      buffer.write 5_u32
      io = Minecraft::IO::Memory.new(buffer.to_slice)

      component = Rosegold::DataComponent.create_component_by_name("painting/variant", 0_u32, io)

      expect(component).to be_a(Rosegold::DataComponents::PaintingVariant)
    end

    it "reads a registry-ref holder and round-trips" do
      buffer = Minecraft::IO::Memory.new
      buffer.write 5_u32
      buffer.write_byte 0x7F_u8
      io = Minecraft::IO::Memory.new(buffer.to_slice)

      component = Rosegold::DataComponents::PaintingVariant.read(io)

      expect(component.raw_bytes.hexstring).to eq("05")
      expect(io.read_byte).to eq(0x7F)

      sink = Minecraft::IO::Memory.new
      component.write(sink)
      expect(sink.to_slice.hexstring).to eq("05")
    end

    it "reads the inline body and round-trips" do
      body = Minecraft::IO::Memory.new
      body.write 0_u32             # holder = inline
      body.write 16_u32            # width
      body.write 16_u32            # height
      body.write "minecraft:kebab" # asset_id
      body.write false             # no title
      body.write false             # no author
      expected = body.to_slice.dup

      wire = Minecraft::IO::Memory.new
      wire.write(expected)
      wire.write_byte 0x7F_u8
      io = Minecraft::IO::Memory.new(wire.to_slice)

      component = Rosegold::DataComponents::PaintingVariant.read(io)

      expect(component.raw_bytes.hexstring).to eq(expected.hexstring)
      expect(io.read_byte).to eq(0x7F)

      sink = Minecraft::IO::Memory.new
      component.write(sink)
      expect(sink.to_slice.hexstring).to eq(expected.hexstring)
    end
  end
end
