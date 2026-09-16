require "../spec_helper"

Spectator.describe "26.3 item components" do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips attack animation through the 26.3 registry" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "01010100280102".hexbytes
    slot = Rosegold::Slot.read(Minecraft::IO::Memory.new(bytes))

    expect(encoded_slot(slot)).to eq(bytes)
  end

  it "round-trips a constant compostable value" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "01010100540100000007".hexbytes
    slot = Rosegold::Slot.read(Minecraft::IO::Memory.new(bytes))

    compostable = slot.components_to_add["compostable"].as(Rosegold::DataComponents::ResolvableIntComponent)
    expect(compostable.value).to eq(7)
    expect(compostable.reference).to be_nil
    expect(encoded_slot(slot)).to eq(bytes)
  end

  it "preserves constant and reference fuel branches" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "01010100550003666f6f013f800000".hexbytes
    slot = Rosegold::Slot.read(Minecraft::IO::Memory.new(bytes))

    fuel = slot.components_to_add["cooking_fuel"].as(Rosegold::DataComponents::FuelComponent)
    expect(fuel.burn_time.reference).to eq("foo")
    expect(fuel.speed_multiplier.value).to eq(1.0_f32)
    expect(fuel.speed_multiplier.reference).to be_nil
    expect(encoded_slot(slot)).to eq(bytes)
  end

  it "consumes all four optional pot decorations" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "010101004c00000000".hexbytes

    expect(encoded_slot(Rosegold::Slot.read(Minecraft::IO::Memory.new(bytes)))).to eq(bytes)
  end

  it "preserves a decorated pot's nested item components and the following component" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "010102004c010501010003070000007801".hexbytes
    io = Minecraft::IO::Memory.new(bytes)
    slot = Rosegold::Slot.read(io)

    expect(io.pos).to eq(bytes.size - 1)
    expect(slot.components_to_add.keys).to eq(["pot_decorations", "waxed"])
    expect(encoded_slot(slot)).to eq(bytes[0...-1])
  end

  it "consumes sign text including filtered messages without losing the next component" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "01010200760800016108000162080001630800016401080001410800014208000143080001440e017801".hexbytes
    io = Minecraft::IO::Memory.new(bytes)
    slot = Rosegold::Slot.read(io)

    expect(io.pos).to eq(bytes.size - 1)
    expect(slot.components_to_add.keys).to eq(["sign_text_front", "waxed"])
    expect(encoded_slot(slot)).to eq(bytes[0...-1])
  end

  it "reads a registry holder without an inline discriminator" do
    Rosegold::Client.protocol_version = 777_u32
    bytes = "010101002b05".hexbytes

    expect(encoded_slot(Rosegold::Slot.read(Minecraft::IO::Memory.new(bytes)))).to eq(bytes)
  end

  it "round-trips direct and named mob-visibility holder sets" do
    Rosegold::Client.protocol_version = 777_u32
    direct = "010101005702053f800000".hexbytes
    named = "010101005700106d696e6563726166743a756e646561643f800000".hexbytes

    expect(encoded_slot(Rosegold::Slot.read(Minecraft::IO::Memory.new(direct)))).to eq(direct)
    expect(encoded_slot(Rosegold::Slot.read(Minecraft::IO::Memory.new(named)))).to eq(named)
  end
end

private def encoded_slot(slot : Rosegold::Slot) : Bytes
  io = Minecraft::IO::Memory.new
  slot.write(io)
  io.to_slice
end
