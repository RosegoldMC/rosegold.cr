require "../spec_helper"

Spectator.describe Rosegold::DataComponentTypes do
  describe "protocol 772 (1.21.8)" do
    # ids 40-43 were historically mis-ordered; verify the corrected order.
    it "orders charged_projectiles/bundle_contents/potion_contents/potion_duration_scale at 40-43" do
      expect(described_class.id_for("charged_projectiles", 772_u32)).to eq(40_u32)
      expect(described_class.id_for("bundle_contents", 772_u32)).to eq(41_u32)
      expect(described_class.id_for("potion_contents", 772_u32)).to eq(42_u32)
      expect(described_class.id_for("potion_duration_scale", 772_u32)).to eq(43_u32)
    end
  end

  describe "protocol 773 (1.21.9)" do
    it "uses the corrected 40-43 ordering" do
      expect(described_class.id_for("charged_projectiles", 773_u32)).to eq(40_u32)
      expect(described_class.name_for(43_u32, 773_u32)).to eq("potion_duration_scale")
    end

    it "has 96 components (no 774-era additions, no zombie_nautilus/variant)" do
      expect(described_class.name_for(95_u32, 773_u32)).to eq("shulker/color")
      expect(described_class.name_for(96_u32, 773_u32)).to be_nil
      expect(described_class.id_for("zombie_nautilus/variant", 773_u32)).to be_nil
    end
  end

  describe "protocol 776 (26.2)" do
    it "inserts sulfur_cube_content at id 78, shifting lock to 79" do
      expect(described_class.id_for("sulfur_cube_content", 776_u32)).to eq(78_u32)
      expect(described_class.name_for(79_u32, 776_u32)).to eq("lock")
    end

    it "has 111 components" do
      expect(described_class.name_for(110_u32, 776_u32)).to eq("shulker/color")
      expect(described_class.name_for(111_u32, 776_u32)).to be_nil
    end
  end
end

Spectator.describe Rosegold::Clientbound::SpawnEntity do
  describe "player entity type id by protocol" do
    it "maps each enabled protocol to the correct player entity type" do
      m = Rosegold::Clientbound::SpawnEntity::ENTITY_TYPE_PLAYER_BY_PROTOCOL
      expect(m[772_u32]).to eq(149_u32)
      expect(m[773_u32]).to eq(151_u32)
      expect(m[774_u32]).to eq(155_u32)
      expect(m[775_u32]).to eq(155_u32)
      expect(m[776_u32]).to eq(156_u32)
    end
  end
end
