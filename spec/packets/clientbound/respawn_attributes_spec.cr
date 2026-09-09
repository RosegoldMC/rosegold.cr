require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::Respawn do
  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  def respawn(data_kept : UInt8)
    Rosegold::Clientbound::Respawn.new(
      0_u32, "minecraft:overworld", 0_i64, 0_u8, -1_i8,
      false, false, false, nil, nil, 0_u32, 63_u32, data_kept
    )
  end

  it "clears attributes that the respawn does not preserve" do
    client.player.apply_attribute_snapshots([
      Rosegold::AttributeSnapshot.new(22_u32, 0.15, [] of Rosegold::AttributeModifier),
    ])

    respawn(0_u8).callback(client)

    expect(client.player.attributes).to be_empty
  end

  it "retains attributes when the respawn requests them" do
    client.player.apply_attribute_snapshots([
      Rosegold::AttributeSnapshot.new(22_u32, 0.15, [] of Rosegold::AttributeModifier),
    ])

    respawn(Rosegold::Clientbound::Respawn::KEEP_ATTRIBUTES).callback(client)

    expect(client.player.attributes[22_u32].base).to eq(0.15)
  end

  it "clears attributes when a fresh login reuses the player" do
    client.player.apply_attribute_snapshots([
      Rosegold::AttributeSnapshot.new(22_u32, 0.15, [] of Rosegold::AttributeModifier),
    ])

    Rosegold::Clientbound::Login.new(
      7, false, ["minecraft:overworld"], 20_u32, 10_u32, 10_u32,
      false, true, false, 0_u32, "minecraft:overworld", 0_i64, 0_u8,
      -1_i8, false, false, false, nil, nil, 0_u32, 63_u32, false
    ).callback(client)

    expect(client.player.attributes).to be_empty
  end
end
