require "../spec_helper"

Spectator.describe Rosegold::Block do
  let(:data) { Rosegold::MCData.default }
  let(:stone) { data.blocks.find! { |block| block.id_str == "stone" } }
  let(:dirt) { data.blocks.find! { |block| block.id_str == "dirt" } }
  let(:obsidian) { data.blocks.find! { |block| block.id_str == "obsidian" } }
  let(:player) { Rosegold::Player.new.tap(&.on_ground=(true)) }
  let(:bare_hand) { Rosegold::Slot.new }
  let(:pickaxe_id) { data.items.find! { |item| item.name == "diamond_pickaxe" }.id }
  let(:efficiency_id) { data.enchantments.find! { |enchantment| enchantment.name == "efficiency" }.id }
  let(:pickaxe) { Rosegold::Slot.new(1_u32, pickaxe_id) }
  let(:enchanted_pickaxe) do
    components = {"enchantments" => Rosegold::DataComponents::Enchantments.new({efficiency_id => 4_u32})} of String => Rosegold::DataComponent
    Rosegold::Slot.new(1_u32, pickaxe_id, components)
  end

  after_each { Rosegold::Client.reset_protocol_version! }

  {% for protocol in Rosegold::ENABLED_PROTOCOLS.keys.sort %}
    describe "protocol {{protocol}}" do
      before_each { Rosegold::Client.protocol_version = {{protocol}}_u32 }

      it "uses the correct attribute IDs and applies synced Efficiency and Aqua Affinity once" do
        player.apply_attribute_snapshots([
          Rosegold::AttributeSnapshot.new({{protocol >= 776 ? 24 : 20}}_u32, 3.0, [
            Rosegold::AttributeModifier.new("minecraft:enchantment.efficiency", 17.0, 0_u8),
          ]),
          Rosegold::AttributeSnapshot.new({{protocol >= 776 ? 7 : 5}}_u32, 2.0),
          Rosegold::AttributeSnapshot.new({{protocol >= 776 ? 34 : 29}}_u32, 0.1, [
            Rosegold::AttributeModifier.new("minecraft:enchantment.aqua_affinity", 4.0, 2_u8),
          ]),
        ])

        expect(stone.break_damage(enchanted_pickaxe, player, submerged: true, aqua_affinity: true)).to be_close(28.0 / 45.0, 1e-6)
        expect(dirt.break_damage(enchanted_pickaxe, player)).to be_close(2.0 / 15.0, 1e-6)
      end

      it "uses the slower divisor with a fast but under-tier pickaxe" do
        gold_id = data.items.find! { |item| item.name == "golden_pickaxe" }.id
        gold = Rosegold::Slot.new(1_u32, gold_id)
        expect(obsidian.can_harvest?(gold)).to be_false
        expect(obsidian.break_damage(gold, player)).to be_close(12.0 / 5000.0, 1e-8)
        expect(obsidian.break_damage(pickaxe, player)).to be_close(8.0 / 1500.0, 1e-8)
      end

      it "uses the vanilla cobweb rules for shears and swords" do
        cobweb = data.blocks.find! { |block| block.id_str == "cobweb" }
        {"shears", "golden_sword"}.each do |name|
          tool_id = data.items.find! { |item| item.name == name }.id
          tool = Rosegold::Slot.new(1_u32, tool_id)
          expect(cobweb.break_damage(tool, player)).to be_close(0.125, 1e-7)
        end
        expect(cobweb.break_damage(bare_hand, player)).to be_close(0.0025, 1e-7)
      end

      {% if protocol >= 773 %}
        it "uses copper's vanilla mining speed" do
          copper_id = data.items.find! { |item| item.name == "copper_pickaxe" }.id
          expect(stone.break_damage(Rosegold::Slot.new(1_u32, copper_id), player)).to be_close(5.0 / 45.0, 1e-7)
        end
      {% end %}

      it "uses synced block reach, including zero, or falls back to gamemode reach" do
        expect(player.block_interaction_range).to eq 4.5
        player.gamemode = 1_i8
        expect(player.block_interaction_range).to eq 5.0
        id = {{protocol >= 776 ? 8 : 6}}_u32
        player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 2.0, [
          Rosegold::AttributeModifier.new("minecraft:creative_mode_block_range", 0.5, 0_u8),
        ])])
        expect(player.block_interaction_range).to eq 2.5
        player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 0.0)])
        expect(player.block_interaction_range).to eq 0.0
        player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 80.0)])
        expect(player.block_interaction_range).to eq 64.0
      end
    end
  {% end %}

  it "uses the higher of Haste and Conduit Power and each Mining Fatigue penalty" do
    player.effects << Rosegold::EntityEffect.new(Rosegold::EntityEffect::Effect::Haste.value, 1_u32, 200_u32, 0_u8)
    player.effects << Rosegold::EntityEffect.new(Rosegold::EntityEffect::Effect::ConduitPower.value, 2_u32, 200_u32, 0_u8)
    expect(stone.break_damage(pickaxe, player)).to be_close(8.0 * 1.6 / 45.0, 1e-7)

    fatigue = Rosegold::EntityEffect.new(Rosegold::EntityEffect::Effect::MiningFatigue.value, 0_u32, 200_u32, 0_u8)
    player.effects << fatigue
    {0.3, 0.09, 0.0027, 0.00081, 0.00081}.each_with_index do |penalty, amplifier|
      fatigue.amplifier = amplifier.to_u32
      expect(stone.break_damage(pickaxe, player)).to be_close(8.0 * 1.6 * penalty / 45.0, 1e-7)
    end
  end

  it "uses explicit eye submersion, with separate Aqua Affinity and airborne penalties" do
    player.in_water = true
    expect(stone.break_damage(pickaxe, player, submerged: false)).to be_close(8.0 / 45.0, 1e-7)
    expect(stone.break_damage(pickaxe, player)).to be_close(8.0 * 0.2 / 45.0, 1e-7)
    player.on_ground = false
    expect(stone.break_damage(pickaxe, player, aqua_affinity: true)).to be_close(8.0 / 225.0, 1e-7)
    expect(stone.break_damage(pickaxe, player)).to be_close(8.0 * 0.2 / 225.0, 1e-7)
  end

  it "uses the first matching speed and drops rules independently, including direct ids and synced block tags" do
    tool_rule = Rosegold::DataComponents::Tool::ToolRule
    stone_id = data.blocks.index!(stone).to_u32
    tool = Rosegold::DataComponents::Tool.new([
      tool_rule.new(blocks_tag: "custom:mineable", has_correct_for_drops: true, correct_for_drops: false),
      tool_rule.new(blocks_type: 2_u32, blocks_ids: [stone_id], has_speed: true, speed: 2.0_f32,
        has_correct_for_drops: true, correct_for_drops: true),
      tool_rule.new(blocks_tag: "custom:mineable", has_speed: true, speed: 8.0_f32),
    ], default_mining_speed: 3.0_f32)
    components = {"tool" => tool} of String => Rosegold::DataComponent
    stack = Rosegold::Slot.new(1_u32, pickaxe_id, components)
    tags = [{name: "custom:mineable", entries: [stone_id]}]

    expect(stone.break_damage(stack, player, block_tags: tags)).to be_close(2.0 / 150.0, 1e-7)
    expect(stone.break_damage(stack, player)).to be_close(2.0 / 45.0, 1e-7)
    expect(dirt.break_damage(stack, player)).to be_close(3.0 / 15.0, 1e-7)
  end

  it "does not fall back to a vanilla tool after its tool component is removed" do
    pickaxe.components_to_remove.add("tool")
    expect(stone.break_damage(pickaxe, player)).to be_close(1.0 / 150.0, 1e-7)
  end

  it "does not produce invalid progress for unbreakable or zero speed blocks" do
    bedrock = data.blocks.find! { |block| block.id_str == "bedrock" }
    torch = data.blocks.find! { |block| block.id_str == "torch" }
    expect(bedrock.break_time(pickaxe, player)).to eq 0
    expect(bedrock.break_damage(pickaxe, player)).to eq 0.0
    expect(torch.break_damage(bare_hand, player)).to eq 1.0

    id = Rosegold::Client.protocol_version >= 776 ? 7_u32 : 5_u32
    player.apply_attribute_snapshots([Rosegold::AttributeSnapshot.new(id, 0.0)])
    expect(stone.break_time(pickaxe, player)).to eq 0
    expect(torch.break_damage(bare_hand, player)).to eq 0.0
  end
end
