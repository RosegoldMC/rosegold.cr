require "./spec_helper"

class Rosegold::Client
  def replace_dimension_for_query_test(dimension : Rosegold::Dimension)
    self.dimension = dimension
  end
end

Spectator.describe "Bot world queries" do
  let(bot_client) { Rosegold::Client.new("localhost") }
  let(bot) { Rosegold::Bot.new(bot_client) }

  before_each do
    dimension = bot.world
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(-1, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
  end

  it "distinguishes loaded air from missing chunks and out-of-height positions" do
    expect(bot.block_at(Rosegold::Vec3i.new(-1, 0, 0)).try(&.name)).to eq("air")
    expect(bot.block_at(Rosegold::Vec3i.new(0, 0, 0))).to be_nil
    expect(bot.block_at(Rosegold::Vec3i.new(-1, -65, 0))).to be_nil
  end

  it "decodes state properties and retains detached state after block updates" do
    state = Rosegold::MCData.default.block_state_names.index!("oak_slab[type=top, waterlogged=true]").to_u16
    bot.world.set_block_state(-1, 0, 0, state)
    snapshot = bot.block_at(Rosegold::Vec3d.new(-0.1, 0.9, 0.1)) || raise "Missing loaded slab"
    bot.world.set_block_state(-1, 0, 0, 0_u16)
    expect(snapshot.position).to eq(Rosegold::Vec3i.new(-1, 0, 0))
    expect(snapshot.state_id).to eq(state)
    expect(snapshot.properties).to eq({"type" => "top", "waterlogged" => "true"})
    expect(snapshot.name).to eq("oak_slab")
  end

  it "bounds searches by radius and count and orders by distance" do
    stone = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }.min_state_id
    [-1, -3, -5].each { |x| bot.world.set_block_state(x, 0, 0, stone) }
    origin = Rosegold::Vec3i.new(-1, 0, 0)
    expect(bot.find_blocks("minecraft:stone", center: origin, radius: 3, limit: 5).map(&.position.x)).to eq([-1, -3])
    expect(bot.find_blocks("stone", center: origin, radius: 5, limit: 1).map(&.position.x)).to eq([-1])
    expect(bot.find_block("stone", center: origin, radius: 0).try(&.position)).to eq(origin)
    expect(bot.find_blocks("stone", radius: 3, limit: 0)).to be_empty
    expect { bot.find_blocks("stone", radius: -1) }.to raise_error(ArgumentError)
  end

  it "snapshots entities and excludes removed entities from subsequent queries" do
    type = Rosegold::Entity.metadata_for_protocol.find! { |entry| entry.name == "minecart" }.id.to_u32
    entity = Rosegold::Entity.new(42_u32, UUID.random, type, bot.location + Rosegold::Vec3d.new(1, 0, 0),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    bot.world.entities[42_u64] = entity
    snapshot = bot.entity(42) || raise "Missing tracked minecart"
    expect(bot.nearest_entity(max_distance: 2)).to eq(snapshot)
    expect(bot.nearest_entity { |entry| entry.type == "horse" }).to be_nil
    expect(bot.nearest_entity(max_distance: 0.5)).to be_nil
    entity.position += Rosegold::Vec3d.new(10, 0, 0)
    bot.world.entities.clear
    expect(snapshot.position).to eq(bot.location + Rosegold::Vec3d.new(1, 0, 0))
    expect(bot.entity(42)).to be_nil
    expect(bot.entities).to be_empty
  end

  it "selects nearest matches consistently across small and large result limits" do
    stone = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }.min_state_id
    positions = (-16..-1).flat_map do |block_x|
      (0..15).map do |block_z|
        bot.world.set_block_state(block_x, 0, block_z, stone)
        Rosegold::Vec3i.new(block_x, 0, block_z)
      end
    end
    center = Rosegold::Vec3d.new(-7.5, 0, 7.5)
    expected = positions.sort_by { |position| {(position.to_f64 - center).length, position.x, position.y, position.z} }
    [1, 7, 31, 256, 1000].each do |limit|
      found = bot.find_blocks("stone", center: center, radius: 20, limit: limit)
      expect(found.map(&.position)).to eq(expected.first(limit))
    end
  end

  it "exposes experience synchronized by the client" do
    bot_client.player.experience_level = 30_u32
    bot_client.player.experience_progress = 0.5_f32
    bot_client.player.total_experience = 1400_u32
    expect(bot.client).to eq(bot_client)
    expect(bot.experience_level).to eq(30_u32)
    expect(bot.experience_progress).to eq(0.5_f32)
    expect(bot.total_experience).to eq(1400_u32)
  end

  it "drops unloaded chunks and uses the current dimension after a change" do
    expect(bot.block_at(Rosegold::Vec3i.new(-1, 0, 0))).not_to be_nil
    bot.world.unload_chunk({-1, 0})
    expect(bot.block_at(Rosegold::Vec3i.new(-1, 0, 0))).to be_nil
    replacement = Rosegold::Dimension.new_nether
    bot_client.replace_dimension_for_query_test(replacement)
    expect(bot.world).to eq(replacement)
    expect(bot.find_blocks("air", radius: 10)).to be_empty
  end
end
