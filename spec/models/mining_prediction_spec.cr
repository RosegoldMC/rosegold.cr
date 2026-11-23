require "../spec_helper"

Spectator.describe "mining prediction" do
  before_each { Rosegold::Client.protocol_version = 776_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  let(mc) { Rosegold::MCData.default }

  def state(name : String) : UInt16
    mc.block_state_names.index!(name).to_u16
  end

  def new_chunk(dimension, cx = 0, cz = 0)
    buf = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(buf) }
    Rosegold::Chunk.new(cx, cz, Minecraft::IO::Memory.new(buf.to_slice), dimension)
  end

  let(dimension) do
    Rosegold::Dimension.new.tap { |dim| dim.load_chunk new_chunk(dim) }
  end
  let(pos) { Rosegold::Vec3i.new(1, 64, 2) }
  let(stone) { state("stone") }
  let(air) { state("air") }

  def put(block : UInt16, at = pos)
    dimension.set_block_state at, block
  end

  def seen(at = pos)
    dimension.mining_block_state at.x, at.y, at.z
  end

  it "replaces a dry block with air without touching the world" do
    put stone
    expect(dimension.predict_block_break(pos, 1)).to be_true
    expect(seen).to eq(air)
    expect(dimension.block_state(pos)).to eq(stone)
  end

  it "ignores unloaded and air positions" do
    expect(dimension.predict_block_break(pos, 1)).to be_false
    expect(dimension.predict_block_break(Rosegold::Vec3i.new(500, 64, 500), 2)).to be_false
    expect(seen).to eq(air)
  end

  it "leaves water behind seagrass, kelp, and waterlogged blocks" do
    water = state("water[level=0]")
    {"seagrass", "kelp[age=3]", "oak_slab[type=top, waterlogged=true]"}.each_with_index do |name, i|
      dimension.clear_mining_predictions
      put state(name)
      expect(seen).to eq(state(name))
      expect(dimension.predict_block_break(pos, i + 1)).to be_true
      expect(seen).to eq(water)
    end
  end

  it "keeps dry waterlogged=false blocks as air" do
    put state("oak_slab[type=top, waterlogged=false]")
    dimension.predict_block_break(pos, 1)
    expect(seen).to eq(air)
  end

  it "keeps lava as lava" do
    lava = state("lava[level=0]")
    put lava
    dimension.predict_block_break(pos, 1)
    expect(seen).to eq(lava)
  end

  it "clears cumulatively and ignores newer predictions" do
    other = Rosegold::Vec3i.new(3, 64, 3)
    third = Rosegold::Vec3i.new(4, 64, 3)
    put stone
    put stone, other
    put stone, third
    dimension.predict_block_break(pos, 5)
    dimension.predict_block_break(other, 9)
    dimension.predict_block_break(third, 7)

    dimension.acknowledge_mining_predictions 7
    expect(seen).to eq(stone)
    expect(seen(third)).to eq(stone)
    expect(seen(other)).to eq(air)
    dimension.acknowledge_mining_predictions 3
    expect(seen(other)).to eq(air)
    dimension.acknowledge_mining_predictions 9
    expect(seen(other)).to eq(stone)
  end

  it "does not let an older acknowledgement end a newer prediction at the same block" do
    put state("seagrass")
    dimension.predict_block_break(pos, 2)
    dimension.predict_block_break(pos, 4)
    dimension.acknowledge_mining_predictions 3
    expect(seen).to eq(state("water[level=0]"))
    dimension.acknowledge_mining_predictions 4
    expect(seen).to eq(state("seagrass"))
  end

  it "keeps authoritative changes before or after the acknowledgement" do
    put stone
    dimension.predict_block_break(pos, 1)
    put state("dirt")
    expect(seen).to eq(air)
    dimension.acknowledge_mining_predictions 1
    expect(seen).to eq(state("dirt"))

    dimension.predict_block_break(pos, 2)
    dimension.acknowledge_mining_predictions 2
    put state("gravel")
    expect(seen).to eq(state("gravel"))
  end

  it "drops predictions when the chunk unloads or is replaced" do
    put stone
    dimension.predict_block_break(pos, 1)
    dimension.unload_chunk({0, 0})
    dimension.load_chunk new_chunk(dimension)
    put stone
    expect(seen).to eq(stone)

    dimension.predict_block_break(pos, 2)
    dimension.load_chunk new_chunk(dimension)
    put stone
    expect(seen).to eq(stone)
  end

  it "does not share predictions across dimensions or after clearing" do
    put stone
    dimension.predict_block_break(pos, 1)
    fresh = Rosegold::Dimension.new
    fresh.load_chunk new_chunk(fresh)
    fresh.set_block_state pos, stone
    expect(fresh.mining_block_state(1, 64, 2)).to eq(stone)
    dimension.clear_mining_predictions
    expect(seen).to eq(stone)
  end

  describe "block interaction predictions" do
    it "keeps the latest write at a position through an older acknowledgement" do
      dirt = state("dirt")
      expect(dimension.predict_interaction_block_state(pos, stone, 2)).to be_true
      expect(dimension.interaction_block_state(pos)).to eq(stone)
      expect(dimension.predict_interaction_block_state(pos, dirt, 4)).to be_true
      expect(dimension.predict_interaction_block_state(pos, stone, 3)).to be_false

      dimension.acknowledge_interaction_predictions 2
      expect(dimension.interaction_block_state(pos)).to eq(dirt)
      dimension.acknowledge_interaction_predictions 4
      expect(dimension.interaction_block_state(pos)).to eq(air)
    end

    it "reveals accepted and rejected writes from BlockChange after acknowledgement" do
      c = client
      world = c.dimension_for_test
      world.load_chunk new_chunk(world)
      { {stone, stone}, {state("dirt"), state("gravel")} }.each_with_index do |(predicted_state, confirmed_state), i|
        sequence = i + 1
        expect(world.predict_interaction_block_state(pos, predicted_state, sequence)).to be_true
        Rosegold::Clientbound::BlockChange.new(pos, confirmed_state).callback(c)
        expect(world.block_state(pos)).to eq(confirmed_state)
        expect(world.interaction_block_state(pos)).to eq(predicted_state)
        Rosegold::Clientbound::AcknowledgeBlockChange.new(sequence).callback(c)
        expect(world.interaction_block_state(pos)).to eq(confirmed_state)
      end
    end

    it "rejects unknown states and positions outside loaded chunk data" do
      unloaded = Rosegold::Vec3i.new(500, pos.y, 500)
      below_world = pos.with_y(dimension.min_y - 1)
      above_world = pos.with_y(dimension.min_y + dimension.world_height)
      expect(dimension.predict_interaction_block_state(pos, stone, 1)).to be_true
      expect(dimension.predict_interaction_block_state(pos, UInt16::MAX, 2)).to be_false
      expect(dimension.interaction_block_state(pos)).to eq(stone)

      {unloaded, below_world, above_world, pos.with_y(Int32::MAX)}.each do |invalid_pos|
        expect(dimension.predict_interaction_block_state(invalid_pos, stone, 3)).to be_false
      end
      {unloaded, below_world, above_world}.each do |invalid_pos|
        expect(dimension.interaction_block_state(invalid_pos)).to be_nil
      end
    end

    it "keeps speculative states out of chunk data and fluid geometry" do
      water = state("water[level=0]")
      eyes = Rosegold::Vec3d.new(1.5, 64.8, 2.5)
      expect(dimension.predict_interaction_block_state(pos, water, 1)).to be_true
      expect(dimension.interaction_block_state(pos.x, pos.y, pos.z)).to eq(water)
      expect(dimension.block_state(pos)).to eq(air)
      expect(dimension.eye_in_water?(eyes)).to be_false

      dimension.clear_interaction_predictions
      expect(dimension.interaction_block_state(pos)).to eq(air)
    end
  end

  describe "#eye_in_water?" do
    it "uses vanilla fluid height at the eye block" do
      put state("water[level=0]")
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.8, 2.5))).to be_true
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.9, 2.5))).to be_false
      put state("water[level=4]")
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.5, 2.5))).to be_false
      put state("water[level=0]"), pos.up
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.95, 2.5))).to be_true
    end

    it "is false for dry blocks, lava, and unloaded chunks" do
      put stone
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.5, 2.5))).to be_false
      put state("lava[level=0]")
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(1.5, 64.5, 2.5))).to be_false
      expect(dimension.eye_in_water?(Rosegold::Vec3d.new(900.5, 64.5, 2.5))).to be_false
    end
  end

  describe Rosegold::Clientbound::AcknowledgeBlockChange do
    it "cumulatively clears pending operations and predictions" do
      c = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "x"})
      c.dimension_for_test.load_chunk new_chunk(c.dimension_for_test)
      c.dimension_for_test.set_block_state pos, stone
      c.dimension_for_test.predict_block_break(pos, 3)
      op = Rosegold::BlockOperation.new(pos, :dig)
      {1, 3, 4}.each { |sequence| c.pending_block_operations[sequence] = op }
      described_class.new(3).callback(c)
      expect(c.pending_block_operations.keys).to eq([4])
      expect(c.dimension_for_test.mining_block_state(1, 64, 2)).to eq(stone)
    end
  end
end
