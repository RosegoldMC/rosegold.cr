require "../spec_helper"

Spectator.describe BlockFace do
  it "converts each face to a namespaced direction vector" do
    expect(BlockFace::Top.to_vec3d).to eq(Rosegold::Vec3d.new(0, 0.5, 0))
    expect(BlockFace::Bottom.to_vec3d).to eq(Rosegold::Vec3d.new(0, -0.5, 0))
    expect(BlockFace::North.to_vec3d).to eq(Rosegold::Vec3d.new(0, 0, -0.5))
    expect(BlockFace::South.to_vec3d).to eq(Rosegold::Vec3d.new(0, 0, 0.5))
    expect(BlockFace::West.to_vec3d).to eq(Rosegold::Vec3d.new(-0.5, 0, 0))
    expect(BlockFace::East.to_vec3d).to eq(Rosegold::Vec3d.new(0.5, 0, 0))
  end

  it "targets the same block-face center in either operand order" do
    block = Rosegold::Vec3i.new(1, 2, 3)
    expected = Rosegold::Vec3d.new(1.5, 3.0, 3.5)
    expect(block + BlockFace::Top).to eq(expected)
    expect(BlockFace::Top + block).to eq(expected)
  end
end
