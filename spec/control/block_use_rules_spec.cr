require "../spec_helper"
require "../../src/rosegold/control/block_use_rules"

Spectator.describe Rosegold::BlockUseRules do
  before_each { Rosegold::Client.protocol_version = Rosegold::Client::LATEST_PROTOCOL }
  after_each { Rosegold::Client.reset_protocol_version! }

  def mc
    Rosegold::MCData.default
  end

  let(clicked) { Rosegold::Vec3i.new(5, 64, 5) }
  let(above) { Rosegold::Vec3i.new(5, 65, 5) }
  let(player) { Rosegold::Player.new }
  let(empty_hand) { Rosegold::Slot.new }
  let(dimension) do
    Rosegold::Dimension.new.tap do |world|
      io = Minecraft::IO::Memory.new
      (world.world_height >> 4).times { Rosegold::Section.empty.write(io) }
      world.load_chunk Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(io.to_slice), world)
    end
  end

  def state(name : String) : UInt16
    mc.block_state_names.index!(name).to_u16
  end

  def put(name : String, position = clicked)
    dimension.set_block_state position, state(name)
  end

  def item(name : String)
    Rosegold::Slot.new(1_u32, mc.items.find! { |entry| entry.name == name }.id)
  end

  def evaluate(main = empty_hand, off = empty_hand, hand : Rosegold::Hand = Rosegold::Hand::MainHand, position = clicked, face : BlockFace = BlockFace::Top)
    Rosegold::BlockUseRules.evaluate(dimension, player, position, face, hand, main, off)
  end

  it "places known ordinary cubes using each enabled version's item and block data" do
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      put "stone"
      {"stone", "cobblestone", "obsidian", "oak_planks", "spruce_planks", "birch_planks"}.each do |name|
        held = item(name)
        decision = evaluate(held)
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
        expect(decision.writes).to eq([{above, state(name)}])
        expect(held.count).to eq(1_u32)
      end
      expect(dimension.block_state(above)).to eq(state("air"))
      expect(dimension.interaction_block_state(above)).to eq(state("air"))
    end
  end

  it "places in the clicked cell when a cached hit now points at any vanilla air state" do
    put "stone"
    mc.air_states.each_with_index do |air, index|
      expect(dimension.predict_interaction_block_state(clicked, air, index + 1)).to be_true
      decision = evaluate(item("obsidian"))
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(decision.writes).to eq([{clicked, state("obsidian")}])
      expect(dimension.block_state(clicked)).to eq(state("stone"))
      expect(dimension.interaction_block_state(clicked)).to eq(air)
    end
  end

  it "uses the selected hand's stack and permits placement during secondary use on an inert block" do
    put "stone"
    player.sneaking = true
    expect(evaluate(empty_hand, item("oak_planks")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(evaluate(item("stone"), item("oak_planks"), Rosegold::Hand::OffHand).writes).to eq([{above, state("oak_planks")}])
  end

  it "fails on confirmed own-player overlap but not on a merely touching face" do
    put "stone"
    player.feet = Rosegold::Vec3d.new(5.5, 66.0, 5.5)
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Success)
    player.feet = Rosegold::Vec3d.new(5.5, 65.99, 5.5)
    decision = evaluate(item("stone"))
    expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Fail)
    expect(decision.writes).to be_empty
  end

  it "stays unknown around other entities rather than inferring which ones block building" do
    put "stone"
    dimension.entities[1_u64] = Rosegold::Entity.new(1_u32, UUID.random, 0_u32, above.to_f64, 0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "rejects a definitely nonreplaceable target but leaves unmodeled targets and neighbors unknown" do
    put "stone"
    put "stone", above
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Fail)
    put "water[level=0]", above
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    put "air", above
    put "sand", Rosegold::Vec3i.new(5, 66, 5)
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "does not predict into unloaded or out-of-height cells or near an unloaded neighbor" do
    edge = Rosegold::Vec3i.new(15, 64, 5)
    put "stone", edge
    expect(evaluate(item("stone"), position: edge, face: BlockFace::East).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    expect(evaluate(item("stone"), position: edge).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    summit = Rosegold::Vec3i.new(5, dimension.min_y + dimension.world_height - 1, 5)
    put "stone", summit
    expect(evaluate(item("stone"), position: summit).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "does not model placement of other item classes, custom components, or restricted modes" do
    put "stone"
    expect(evaluate(item("oak_log")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    patched = item("stone")
    patched.components_to_remove << "block_state"
    expect(evaluate(patched).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    player.gamemode = 1_i8
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Success)
    player.creative_mode = false
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    player.gamemode = 2_i8
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "toggles only OPEN on verified hand-openable trapdoors, including waterlogged and powered states" do
    names = %w(oak_trapdoor warped_trapdoor waxed_oxidized_copper_trapdoor)
    names << "poplar_trapdoor" if Rosegold::Client.protocol_version >= 777_u32
    names.each do |name|
      closed = "#{name}[facing=east, half=top, open=false, powered=true, waterlogged=true]"
      opened = closed.sub("open=false", "open=true")
      put closed
      decision = evaluate
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(decision.writes).to eq([{clicked, state(opened)}])
      expect(dimension.block_state(clicked)).to eq(state(closed))
      expect(dimension.predict_interaction_block_state(clicked, state(opened), 1)).to be_true
      expect(evaluate.writes).to eq([{clicked, state(closed)}])
      dimension.acknowledge_interaction_predictions(1)
    end
    put "iron_trapdoor[facing=east, half=top, open=false, powered=true, waterlogged=true]"
    expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(evaluate.writes).to be_empty
  end

  sample Rosegold::Client::SUPPORTED_PROTOCOLS do |protocol|
    it "toggles both halves from either side for every hand-openable door variant" do
      Rosegold::Client.protocol_version = protocol
      woods = %w(oak spruce birch jungle acacia cherry dark_oak pale_oak mangrove bamboo crimson warped)
      copper = %w(copper exposed_copper weathered_copper oxidized_copper
        waxed_copper waxed_exposed_copper waxed_weathered_copper waxed_oxidized_copper)
      names = woods + copper
      names << "poplar" if protocol >= 777_u32
      names.each do |name|
        %w(false true).each do |open|
          lower = "#{name}_door[facing=east, half=lower, hinge=right, open=#{open}, powered=true]"
          upper = lower.sub("half=lower", "half=upper")
          next_open = open == "false" ? "true" : "false"
          lower_next = state(lower.sub("open=#{open}", "open=#{next_open}"))
          upper_next = state(upper.sub("open=#{open}", "open=#{next_open}"))
          put lower
          put upper, above
          decision = evaluate
          expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
          expect(decision.writes).to eq([{clicked, lower_next}, {above, upper_next}])
          decision = evaluate(position: above)
          expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
          expect(decision.writes).to eq([{above, upper_next}, {clicked, lower_next}])
        end
      end
      put "iron_door[facing=east, half=lower, hinge=right, open=false, powered=false]"
      expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Pass)
      expect(evaluate.writes).to be_empty
    end
  end

  it "copies the clicked door's toggled variant and properties to a loaded opposite door half" do
    lower = "oak_door[facing=east, half=lower, hinge=right, open=false, powered=true]"
    put lower
    put "iron_door[facing=south, half=upper, hinge=left, open=true, powered=false]", above

    expect(evaluate.writes).to eq([
      {clicked, state(lower.sub("open=false", "open=true"))},
      {above, state(lower.sub("half=lower", "half=upper").sub("open=false", "open=true"))},
    ])
  end

  it "only toggles the clicked half when the relative cell is missing or is not an opposite door half" do
    lower = "oak_door[facing=east, half=lower, hinge=right, open=false, powered=false]"
    opened = lower.sub("open=false", "open=true")
    put lower
    {"air", "stone", lower}.each do |neighbor|
      put neighbor, above
      decision = evaluate
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(decision.writes).to eq([{clicked, state(opened)}])
    end
    dimension.set_block_state above, UInt16::MAX
    expect(evaluate.writes).to eq([{clicked, state(opened)}])

    summit = Rosegold::Vec3i.new(clicked.x, dimension.min_y + dimension.world_height - 1, clicked.z)
    put lower, summit
    decision = evaluate(position: summit)
    expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
    expect(decision.writes).to eq([{summit, state(opened)}])
  end

  it "opens verified wooden fence gates toward the player direction only when facing opposite" do
    woods = %w(oak spruce birch jungle acacia cherry dark_oak pale_oak mangrove bamboo crimson warped)
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      names = woods.dup
      names << "poplar" if protocol >= 777_u32
      names.each do |name|
        closed = "#{name}_fence_gate[facing=north, in_wall=true, open=false, powered=true]"
        opened = closed.sub("facing=north", "facing=south").sub("open=false", "open=true")
        player.look = Rosegold::Look::SOUTH
        put closed
        decision = evaluate
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
        expect(decision.writes).to eq([{clicked, state(opened)}])
        put opened
        player.look = Rosegold::Look::NORTH
        expect(evaluate.writes).to eq([{clicked, state(opened.sub("open=true", "open=false"))}])
      end
    end
  end

  it "rounds the horizontal fence gate direction at vanilla yaw boundaries, independent of pitch" do
    cases = {
      {-45.001_f32, "west", "east"}, {-45_f32, "north", "south"},
      {44.999_f32, "north", "south"}, {45_f32, "east", "west"},
      {135_f32, "south", "north"}, {225_f32, "west", "east"},
      {405_f32, "north", "north"}, {193273528320_f32, "north", "south"},
    }
    cases.each do |yaw, facing, opened_facing|
      closed = "oak_fence_gate[facing=#{facing}, in_wall=false, open=false, powered=false]"
      opened = closed.sub("facing=#{facing}", "facing=#{opened_facing}").sub("open=false", "open=true")
      put closed
      player.look = Rosegold::Look.new(yaw, 90_f32)
      expect(evaluate.writes).to eq([{clicked, state(opened)}])
    end
  end

  it "skips manual door and gate use off hand or with either hand populated during secondary use" do
    {
      "oak_door[facing=east, half=lower, hinge=right, open=false, powered=false]",
      "oak_fence_gate[facing=north, in_wall=false, open=false, powered=false]",
    }.each do |name|
      put name
      held = item("stick")
      player.sneaking = false
      expect(evaluate(held).result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(evaluate(empty_hand, held, Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Pass)
      expect(evaluate(empty_hand, item("stone"), Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
      player.sneaking = true
      expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Success)
      [{held, empty_hand}, {empty_hand, held}].each do |main, off|
        decision = evaluate(main, off)
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Pass)
        expect(decision.writes).to be_empty
      end
    end
  end

  it "needs the main hand for default block use and skips it with either hand occupied while sneaking" do
    put "oak_trapdoor[facing=east, half=top, open=false, powered=false, waterlogged=false]"
    expect(evaluate(hand: Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    player.sneaking = true
    expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Success)
    expect(evaluate(empty_hand, item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(evaluate(item("stone")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "passes a plain offhand apple or bread to item use on blocks whose own use needs the main hand" do
    blocks = {
      "stone_button[face=wall, facing=south, powered=false]",
      "oak_trapdoor[facing=east, half=top, open=false, powered=false, waterlogged=false]",
      "chest[type=single, facing=north, waterlogged=false]",
      "lever[face=floor, facing=north, powered=false]",
      "lectern[facing=north, has_book=true, powered=false]",
    }
    blocks.each do |name|
      put name
      {"apple", "bread"}.each do |food|
        decision = evaluate(empty_hand, item(food), Rosegold::Hand::OffHand)
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Pass)
        expect(decision.writes).to be_empty
      end
      expect(evaluate(item("apple"), item("apple")).result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(evaluate(empty_hand, item("carrot"), Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
      renamed = item("apple")
      renamed.components_to_remove << "food"
      expect(evaluate(empty_hand, renamed, Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    end
    dimension.set_block_state clicked, mc.blocks.find! { |entry| entry.id_str == "note_block" }.min_state_id
    expect(evaluate(empty_hand, item("apple"), Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    put "cauldron"
    expect(evaluate(empty_hand, item("apple"), Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "passes a plain apple on an inert block and skips block use for it while sneaking" do
    put "stone"
    expect(evaluate(item("apple")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    put "stone_button[face=wall, facing=south, powered=false]"
    player.sneaking = true
    expect(evaluate(item("bread")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(evaluate(item("stick")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    expect(evaluate(item("carrot")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "passes only proven inert items (plain items, hunger foods, shield) to item use, never block items" do
    {"stone", "dirt", "grass_block[snowy=false]"}.each do |name|
      put name
      {"stick", "shield", "apple", "bread", "iron_sword", "coal", "cooked_beef"}.each do |held|
        decision = evaluate(item(held))
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Pass)
        expect(decision.writes).to be_empty
      end
    end
    put "stone_button[face=wall, facing=south, powered=false]"
    expect(evaluate(empty_hand, item("shield"), Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    put "stone"
    expect(evaluate(item("carrot")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    expect(evaluate(item("bucket")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    patched = item("stick")
    patched.components_to_remove << "lore"
    expect(evaluate(patched).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "passes an empty main hand through block use on inert blocks and leaves unmodeled blocks unknown" do
    {"stone", "dirt", "grass_block[snowy=false]", "sand", "netherrack", "air"}.each do |name|
      put name
      expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Pass)
      expect(evaluate(empty_hand, empty_hand, Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    end
    put "note_block[instrument=harp, note=0, powered=false]"
    expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Unknown)
  end

  it "places the widened plain cubes but treats grass-like clicked blocks as pass-only" do
    put "dirt"
    {"granite", "dirt", "coarse_dirt", "sandstone", "bricks", "jungle_planks", "pale_oak_planks"}.each do |name|
      next unless mc.items.any? { |entry| entry.name == name }
      expect(evaluate(item(name)).writes).to eq([{above, state(name)}])
    end
    put "grass_block[snowy=false]"
    expect(evaluate(item("dirt")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    expect(evaluate(item("stick")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
  end

  it "presses a button once and consumes an already powered hit without a swing or a write" do
    {"stone_button", "polished_blackstone_button", "cherry_button"}.each do |name|
      unpowered = "#{name}[face=wall, facing=south, powered=false]"
      powered = unpowered.sub("powered=false", "powered=true")
      put unpowered
      decision = evaluate
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(decision.writes).to eq([{clicked, state(powered)}])
      expect(dimension.predict_interaction_block_state(clicked, state(powered), 1)).to be_true
      decision = evaluate
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Consume)
      expect(decision.writes).to be_empty
      expect(dimension.block_state(clicked)).to eq(state(unpowered))
      dimension.acknowledge_interaction_predictions(1)
    end
  end

  it "uses verified menus and levers without writing local states" do
    {"lever[face=floor, facing=north, powered=false]", "enchanting_table", "crafting_table", "chest[type=single, facing=north, waterlogged=false]", "lectern[facing=north, has_book=true, powered=false]"}.each do |name|
      put name
      decision = evaluate
      expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
      expect(decision.writes).to be_empty
    end
  end

  it "consumes a plain apple or bread in the main hand on a bookless lectern" do
    Rosegold::Client::SUPPORTED_PROTOCOLS.each do |protocol|
      Rosegold::Client.protocol_version = protocol
      put "lectern[facing=north, has_book=false, powered=false]"
      expect(evaluate.result).to eq(Rosegold::BlockUseRules::Result::Pass)
      {"apple", "bread"}.each do |name|
        food = item(name)
        decision = evaluate(food)
        expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Consume)
        expect(decision.writes).to be_empty
        expect(evaluate(empty_hand, food, Rosegold::Hand::OffHand).result).to eq(Rosegold::BlockUseRules::Result::Pass)
      end
      expect(evaluate(item("carrot")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
      patched = item("apple")
      patched.components_to_remove << "food"
      expect(evaluate(patched).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    end
  end

  it "uses only the selected bucket for cauldron results and never writes their states" do
    put "cauldron"
    expect(evaluate(empty_hand, item("water_bucket")).result).to eq(Rosegold::BlockUseRules::Result::Pass)
    decision = evaluate(empty_hand, item("water_bucket"), Rosegold::Hand::OffHand)
    expect(decision.result).to eq(Rosegold::BlockUseRules::Result::Success)
    expect(decision.writes).to be_empty
    expect(dimension.block_state(clicked)).to eq(state("cauldron"))
    patched = item("water_bucket")
    patched.components_to_remove << "use_remainder"
    expect(evaluate(patched).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
    expect(evaluate(item("lava_bucket")).result).to eq(Rosegold::BlockUseRules::Result::Success)
    put "water[level=0]", above
    expect(evaluate(item("lava_bucket")).result).to eq(Rosegold::BlockUseRules::Result::Consume)
    expect(evaluate(item("powder_snow_bucket")).result).to eq(Rosegold::BlockUseRules::Result::Consume)
    %w(water_cauldron powder_snow_cauldron).each do |name|
      block = mc.blocks.find! { |entry| entry.id_str == name }
      dimension.set_block_state clicked, block.min_state_id
      expect(evaluate(item("bucket")).result).to eq(Rosegold::BlockUseRules::Result::Unknown)
      dimension.set_block_state clicked, block.max_state_id
      expect(evaluate(item("bucket")).result).to eq(Rosegold::BlockUseRules::Result::Success)
    end
    put "lava_cauldron"
    expect(evaluate(item("bucket")).result).to eq(Rosegold::BlockUseRules::Result::Success)
  end
end
