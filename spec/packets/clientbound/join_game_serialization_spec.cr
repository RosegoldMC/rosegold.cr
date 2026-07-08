require "../../spec_helper"

Spectator.describe "Login Serialization" do
  after_each { Rosegold::Client.reset_protocol_version! }
  it "can read and write Login packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Captured Login packet data from log
    # 2025-08-05T00:01:18.710887Z   WARN - Packet bytes (141 bytes)
    hex_data = "2b00000bfa0003136d696e6563726166743a6f766572776f726c64116d696e6563726166743a7468655f656e64146d696e6563726166743a7468655f6e6574686572140a0a00010000136d696e6563726166743a6f766572776f726c64c2cbb3304082e5ad00ff000101136d696e6563726166743a6f766572776f726c640000000000000fed00c1ffffff0f00"

    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte is 0x2B)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::Login.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes - rewritten includes packet ID, so compare with original
    expect(rewritten_bytes).to eq(original_bytes)
  end

  it "round-trips the online_mode field on protocol 776" do
    Rosegold::Client.protocol_version = 776_u32

    packet = Rosegold::Clientbound::Login.new(
      entity_id: 42,
      hardcore: false,
      dimension_names: ["minecraft:overworld"],
      max_players: 20_u32,
      view_distance: 10_u32,
      simulation_distance: 10_u32,
      reduced_debug_info: false,
      enable_respawn_screen: true,
      do_limited_crafting: false,
      dimension_type: 0_u32,
      dimension_name: "minecraft:overworld",
      hashed_seed: 0_i64,
      gamemode: 0_u8,
      previous_gamemode: -1_i8,
      is_debug: false,
      is_flat: true,
      has_death_location: false,
      death_dimension_name: nil,
      death_location: nil,
      portal_cooldown: 0_u32,
      sea_level: 63_u32,
      enforces_secure_chat: true,
      online_mode: true
    )

    bytes = packet.write
    io = Minecraft::IO::Memory.new(bytes[1..]) # skip packet id
    parsed = Rosegold::Clientbound::Login.read(io)

    expect(parsed.online_mode?).to be_true
    expect(parsed.enforces_secure_chat?).to be_true
    expect(parsed.sea_level).to eq(63_u32)
    expect(parsed.write).to eq(bytes)
  end

  it "does not emit online_mode below protocol 776" do
    Rosegold::Client.protocol_version = 775_u32

    base = {
      entity_id:             1,
      hardcore:              false,
      dimension_names:       ["minecraft:overworld"],
      max_players:           20_u32,
      view_distance:         10_u32,
      simulation_distance:   10_u32,
      reduced_debug_info:    false,
      enable_respawn_screen: true,
      do_limited_crafting:   false,
      dimension_type:        0_u32,
      dimension_name:        "minecraft:overworld",
      hashed_seed:           0_i64,
      gamemode:              0_u8,
      previous_gamemode:     -1_i8,
      is_debug:              false,
      is_flat:               true,
      has_death_location:    false,
      death_dimension_name:  nil,
      death_location:        nil,
      portal_cooldown:       0_u32,
      sea_level:             63_u32,
      enforces_secure_chat:  true,
    }

    bytes_775 = Rosegold::Clientbound::Login.new(**base).write

    Rosegold::Client.protocol_version = 776_u32
    bytes_776 = Rosegold::Clientbound::Login.new(**base, online_mode: false).write

    # 776 inserts exactly one extra byte (online_mode) vs 775
    expect(bytes_776.size).to eq(bytes_775.size + 1)
  end
end
