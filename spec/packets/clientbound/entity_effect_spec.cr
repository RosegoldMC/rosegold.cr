require "../../spec_helper"
require "log/spec"

Spectator.describe Rosegold::Clientbound::EntityEffect do
  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  def tracked_entity(entity_id)
    Rosegold::Entity.new(
      entity_id, UUID.random, 1_u32,
      Rosegold::Vec3d.new(0.0, 0.0, 0.0),
      0.0_f32, 0.0_f32, 0.0_f32,
      Rosegold::Vec3d.new(0.0, 0.0, 0.0)
    )
  end

  it "applies a self effect without warning about an untracked player" do
    c = client
    c.player.entity_id = 99_u64

    Log.capture("rosegold") do |logs|
      described_class.new(99_u64, 3_u32, 2_u32, 600_u32, 0_u8).callback(c)
      logs.empty
    end

    effect = c.player.effects.first
    expect(effect.effect).to eq(Rosegold::EntityEffect::Effect::MiningFatigue)
    expect(effect.amplifier).to eq(2_u32)
    expect(effect.duration).to eq(600_u32)
  end

  it "applies an effect to a tracked non-player entity" do
    c = client
    entity = tracked_entity(7_u32)
    c.dimension_for_test.entities[7_u64] = entity

    described_class.new(7_u64, 2_u32, 1_u32, 400_u32, 0_u8).callback(c)

    effect = entity.effects.first
    expect(effect.effect).to eq(Rosegold::EntityEffect::Effect::Haste)
    expect(effect.amplifier).to eq(1_u32)
    expect(effect.duration).to eq(400_u32)
  end

  it "warns for an untracked non-player entity" do
    c = client
    c.player.entity_id = 99_u64

    Log.capture("rosegold") do |logs|
      described_class.new(7_u64, 2_u32, 1_u32, 400_u32, 0_u8).callback(c)
      logs.check(:warn, "Received entity effect packet for unknown entity ID 7")
      logs.empty
    end

    expect(c.player.effects).to be_empty
  end
end
