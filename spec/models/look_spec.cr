require "../spec_helper"

Spectator.describe Rosegold::Look do
  describe ".wrap_yaw" do
    it "matches Minecraft yaw wrapping" do
      {
        -720.0_f32 => 0.0_f32,
        -540.0_f32 => -180.0_f32,
        -197.0_f32 => 163.0_f32,
        -180.0_f32 => -180.0_f32,
         180.0_f32 => -180.0_f32,
         197.0_f32 => -163.0_f32,
         540.0_f32 => -180.0_f32,
         720.0_f32 => 0.0_f32,
      }.each do |yaw, expected|
        expect(described_class.wrap_yaw(yaw)).to eq(expected)
      end
    end

    it "replaces non-finite yaw with zero" do
      expect(described_class.wrap_yaw(Float32::NAN)).to eq(0.0_f32)
      expect(described_class.wrap_yaw(Float32::INFINITY)).to eq(0.0_f32)
      expect(described_class.wrap_yaw(-Float32::INFINITY)).to eq(0.0_f32)
    end
  end
end
