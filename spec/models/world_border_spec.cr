require "../spec_helper"

Spectator.describe Rosegold::WorldBorder do
  let(border) { Rosegold::WorldBorder.new }

  def pos(x : Int32, z : Int32, y = 0)
    Rosegold::Vec3i.new(x, y, z)
  end

  it "uses vanilla's default bounds on both horizontal axes" do
    expect(border.outside?(pos(-29_999_984, 29_999_983, Int32::MIN))).to be_false
    expect(border.outside?(pos(29_999_983, -29_999_984, Int32::MAX))).to be_false
    expect(border.outside?(pos(-29_999_985, 0))).to be_true
    expect(border.outside?(pos(0, -29_999_985))).to be_true
    expect(border.outside?(pos(29_999_984, 0))).to be_true
    expect(border.outside?(pos(0, 29_999_984))).to be_true
  end

  it "compares integers directly with fractional bounds" do
    border.set_center(2.25, -3.75)
    border.resize(5.5)

    expect(border.outside?(pos(0, -6))).to be_false
    expect(border.outside?(pos(4, -2))).to be_false
    expect(border.outside?(pos(-1, -6))).to be_true
    expect(border.outside?(pos(0, -7))).to be_true
    expect(border.outside?(pos(5, -2))).to be_true
    expect(border.outside?(pos(4, -1))).to be_true
  end

  it "clamps both axes to the absolute cap from initialization" do
    border.initialize_bounds(8.0, -8.0, 4.0, 40.0, 0_i64, 10, 774_u32)
    expect(border.outside?(pos(-10, -10))).to be_false
    expect(border.outside?(pos(9, 9))).to be_false
    expect(border.outside?(pos(10, 0))).to be_true
    expect(border.outside?(pos(0, -11))).to be_true

    border.set_center(20.0, 0.0)
    border.resize(4.0)
    expect(border.outside?(pos(10, 0))).to be_true
  end

  it "fails open on invalid geometry" do
    border.resize(-1.0)
    expect(border.outside?(pos(20, 20))).to be_false
    border.resize(Float64::INFINITY)
    expect(border.outside?(pos(50_000_000, 50_000_000))).to be_false
    border.resize(2.0)
    border.set_center(0.0, Float64::NAN)
    expect(border.outside?(pos(20, 20))).to be_false
    border.initialize_bounds(0.0, 0.0, 2.0, 2.0, 0_i64, -10, 774_u32)
    expect(border.outside?(pos(20, 20))).to be_false
  end

  sample [772_u32, 773_u32] do |protocol|
    it "samples legacy expansion and shrinkage at integer milliseconds" do
      now = 1_000_i64
      timed = Rosegold::WorldBorder.new(-> { now })
      timed.initialize_bounds(0.0, 0.0, 10.0, 20.0, 1_000_i64, 100, protocol)
      expect(timed.outside?(pos(-7, 0))).to be_true
      now = 1_399_i64
      expect(timed.outside?(pos(-7, 0))).to be_true
      now = 1_400_i64
      expect(timed.outside?(pos(-7, 0))).to be_false
      expect(timed.outside?(pos(7, 0))).to be_true
      now = 2_000_i64
      expect(timed.outside?(pos(9, 0))).to be_false

      timed.lerp(20.0, 10.0, 1_000_i64, protocol)
      now = 2_999_i64
      expect(timed.outside?(pos(0, 5))).to be_false
      now = 3_000_i64
      expect(timed.outside?(pos(0, 5))).to be_true
      expect(timed.outside?(pos(0, -5))).to be_false
    end
  end

  it "replaces a transition with the new packet's starting size" do
    now = 1_000_i64
    timed = Rosegold::WorldBorder.new(-> { now })
    timed.lerp(10.0, 20.0, 1_000_i64, 773_u32)
    now = 1_500_i64
    expect(timed.outside?(pos(4, 0))).to be_false

    timed.lerp(8.0, 10.0, 1_000_i64, 773_u32)
    expect(timed.outside?(pos(4, 0))).to be_true
    timed.set_center(1.0, 0.0)
    expect(timed.outside?(pos(4, 0))).to be_false
    timed.resize(2.0)
    now = 2_000_i64
    expect(timed.outside?(pos(4, 0))).to be_true
  end

  it "keeps a genuine modern transition unknown until a static update" do
    timed = Rosegold::WorldBorder.new(-> : Int64 { raise "modern bounds must not read the monotonic clock" })
    timed.resize(4.0)
    expect(timed.outside?(pos(20, 20))).to be_true
    timed.lerp(4.0, 8.0, 1_i64, 774_u32)
    timed.set_center(20.0, 10.0)
    expect(timed.outside?(pos(20, 20))).to be_false
    timed.resize(8.0)
    expect(timed.outside?(pos(20, 20))).to be_true

    timed.initialize_bounds(0.0, 0.0, 10.0, 2.0, 1_i64, 100, 774_u32)
    expect(timed.outside?(pos(1, 0))).to be_false
    timed.initialize_bounds(0.0, 0.0, 10.0, 2.0, -1_i64, 100, 774_u32)
    expect(timed.outside?(pos(1, 0))).to be_true
  end

  it "uses the target for degenerate direct lerps" do
    border.lerp(10.0, 2.0, 0_i64, 773_u32)
    expect(border.outside?(pos(1, 0))).to be_true
    border.lerp(2.0, 6.0, -1_i64, 774_u32)
    expect(border.outside?(pos(2, 0))).to be_false
    border.lerp(2.0, 2.0, 1_i64, 774_u32)
    expect(border.outside?(pos(1, 0))).to be_true
  end
end
