require "../../spec_helper"

# Regression: a vanilla client crashes ("The validated expression is false") when
# SpectateServer replays a painting with data=0 (DOWN, a vertical facing). The spawn
# packet's data field carries the painting/item-frame facing, so the tracked entity
# must retain it for faithful replay instead of defaulting to 0.
Spectator.describe "SpawnEntity data field" do
  after_each { Rosegold::Client.reset_protocol_version! }

  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  PAINTING_TYPE_12111 = 93_u32

  it "retains the spawn data field on the tracked entity" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 42_u64,
      uuid: UUID.random,
      entity_type: PAINTING_TYPE_12111,
      x: 0.0, y: 0.0, z: 0.0,
      pitch: 0.0, yaw: 0.0, head_yaw: 0.0,
      data: 3_u32, # SOUTH — a horizontal facing the vanilla client accepts
      velocity_x: 0.0, velocity_y: 0.0, velocity_z: 0.0
    )

    packet.callback(client)

    expect(client.dimension_for_test.entities[42_u64].data).to eq(3_u32)
  end
end
