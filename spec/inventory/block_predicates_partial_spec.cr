require "../spec_helper"

# M8 (issue #338): can_place_on / can_break carry a DataComponentMatchers with a
# partial-predicate map. It used to raise on any non-empty partial map, degrading
# the whole container to RawPacket. Each partial entry is uniform on the wire —
# Either type-ref (bool + VarInt registry id) + predicate value as one network NBT
# tag (ByteBufCodecs.fromCodecWithRegistries) — so it can be skipped opaquely for
# every predicate type. Verified against 1.21.11 (proto 774) decompiled source.
Spectator.describe Rosegold::DataComponents::BlockPredicates do
  before_each { Rosegold::Client.protocol_version = 774_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  # Appends an unnamed (network-format) NBT tag: type byte then payload, no name.
  def write_unnamed_nbt(io, tag)
    io.write_byte tag.tag_type
    tag.write io
  end

  def sample_value_nbt
    Minecraft::NBT::CompoundTag.new(
      {"min" => Minecraft::NBT::IntTag.new(5).as(Minecraft::NBT::Tag)} of String => Minecraft::NBT::Tag
    )
  end

  it "reads a predicate with a non-empty partial map and stops exactly" do
    buffer = Minecraft::IO::Memory.new
    buffer.write 1_u32 # predicate count
    buffer.write false # has_blocks
    buffer.write false # has_properties
    buffer.write false # has_nbt
    buffer.write 0_u32 # exact matcher count
    buffer.write 1_u32 # partial matcher count
    buffer.write true  # Either: predicate-type registry
    buffer.write 0_u32 # type registry id (opaque)
    write_unnamed_nbt(buffer, sample_value_nbt)
    buffer.write_byte 0x7F_u8 # sentinel

    io = Minecraft::IO::Memory.new(buffer.to_slice)
    component = Rosegold::DataComponents::BlockPredicates.read(io)

    expect(component).to be_a(Rosegold::DataComponents::BlockPredicates)
    expect(io.read_byte).to eq(0x7F)
  end

  it "reads both Either branches and multiple partial entries" do
    buffer = Minecraft::IO::Memory.new
    buffer.write 1_u32 # predicate count
    buffer.write false # has_blocks
    buffer.write false # has_properties
    buffer.write false # has_nbt
    buffer.write 0_u32 # exact matcher count
    buffer.write 2_u32 # partial matcher count
    buffer.write true  # entry 1: predicate-type registry
    buffer.write 0_u32
    write_unnamed_nbt(buffer, sample_value_nbt)
    buffer.write false # entry 2: component-type registry (AnyValue)
    buffer.write 4_u32
    write_unnamed_nbt(buffer, sample_value_nbt)
    buffer.write_byte 0x7F_u8

    io = Minecraft::IO::Memory.new(buffer.to_slice)
    component = Rosegold::DataComponents::BlockPredicates.read(io)

    expect(component).to be_a(Rosegold::DataComponents::BlockPredicates)
    expect(io.read_byte).to eq(0x7F)
  end

  it "still reads the common empty-map case" do
    buffer = Minecraft::IO::Memory.new
    buffer.write 1_u32 # predicate count
    buffer.write false # has_blocks
    buffer.write false # has_properties
    buffer.write false # has_nbt
    buffer.write 0_u32 # exact matcher count
    buffer.write 0_u32 # partial matcher count
    buffer.write_byte 0x7F_u8

    io = Minecraft::IO::Memory.new(buffer.to_slice)
    component = Rosegold::DataComponents::BlockPredicates.read(io)

    expect(component).to be_a(Rosegold::DataComponents::BlockPredicates)
    expect(io.read_byte).to eq(0x7F)
  end

  it "dispatches can_break and can_place_on by name" do
    %w[can_break can_place_on].each do |name|
      id = Rosegold::DataComponentTypes.id_for(name, 774_u32) || raise "no #{name} id"
      buffer = Minecraft::IO::Memory.new
      buffer.write 0_u32 # zero predicates
      io = Minecraft::IO::Memory.new(buffer.to_slice)

      component = Rosegold::DataComponent.create_component(id, io)
      expect(component).to be_a(Rosegold::DataComponents::BlockPredicates)
    end
  end
end
