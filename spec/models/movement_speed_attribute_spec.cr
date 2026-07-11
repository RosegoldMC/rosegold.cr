require "../spec_helper"

Spectator.describe Rosegold::AttributeSnapshot do
  describe "#effective_value" do
    it "combines all three operations as (base + adds) * (1 + mul_base) * Prod(1 + mul_total)" do
      snapshot = Rosegold::AttributeSnapshot.new(22_u32, 0.1, [
        Rosegold::AttributeModifier.new("a", 0.05, 0_u8),
        Rosegold::AttributeModifier.new("b", 0.5, 1_u8),
        Rosegold::AttributeModifier.new("c", 0.2, 2_u8),
        Rosegold::AttributeModifier.new("d", -0.1, 2_u8),
      ])

      expected = (0.1 + 0.05) * (1.0 + 0.5) * (1.0 + 0.2) * (1.0 - 0.1)
      expect(snapshot.effective_value).to be_close(expected, 1e-9)
    end

    it "returns the base when there are no modifiers" do
      snapshot = Rosegold::AttributeSnapshot.new(22_u32, 0.1, [] of Rosegold::AttributeModifier)
      expect(snapshot.effective_value).to be_close(0.1, 1e-9)
    end

    it "skips excluded modifier ids" do
      snapshot = Rosegold::AttributeSnapshot.new(22_u32, 0.1, [
        Rosegold::AttributeModifier.new("minecraft:sprinting", 0.3, 2_u8),
      ])

      expect(snapshot.effective_value).to be_close(0.13, 1e-9)
      expect(snapshot.effective_value(excluding: Set{"minecraft:sprinting"})).to be_close(0.1, 1e-9)
    end
  end
end

Spectator.describe Rosegold::Player do
  describe "#ground_movement_speed" do
    before_each { Rosegold::Client.protocol_version = 772_u32 }
    after_each { Rosegold::Client.reset_protocol_version! }

    it "uses the synced attribute when present, excluding the sprint modifier" do
      player = Rosegold::Player.new
      player.apply_attribute_snapshots([
        Rosegold::AttributeSnapshot.new(22_u32, 0.1, [
          Rosegold::AttributeModifier.new("minecraft:sprinting", 0.3, 2_u8),
          Rosegold::AttributeModifier.new("minecraft:speed_effect", 0.4, 2_u8),
        ]),
      ])

      expect(player.ground_movement_speed(0.1)).to be_close(0.1 * 1.4, 1e-9)
    end

    it "falls back to the effect formula when no attribute is synced" do
      player = Rosegold::Player.new
      expect(player.ground_movement_speed(0.1)).to be_close(0.1, 1e-9)
    end
  end
end
