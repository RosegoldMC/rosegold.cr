require "./spec_helper"

class MiningResetSpecClient < Rosegold::Client
  getter transport = Minecraft::IO::Memory.new
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def initialize
    super("localhost", offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "miningreset"})
    @connection = Rosegold::Connection::Client.new(transport, Rosegold::ProtocolState::PLAY, protocol_version, self)
    set_protocol_state(Rosegold::ProtocolState::PLAY)
  end

  def leave_play
    set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
  end

  def replace_connection : Rosegold::Connection::Client
    old = connection
    @connection = Rosegold::Connection::Client.new(Minecraft::IO::Memory.new, Rosegold::ProtocolState::PLAY, protocol_version, self)
    old
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    super
    sent_packets << packet
  end

  def interactions_for_test
    interactions
  end

  def physics_paused? : Bool
    physics.paused?
  end

  def resume_physics
    physics.paused = false
  end
end

Spectator.describe "mining session reset" do
  let(client) { MiningResetSpecClient.new }

  def track_operation(client)
    sequence = client.next_sequence
    client.pending_block_operations[sequence] = Rosegold::BlockOperation.new(Rosegold::Vec3i.new(1, 2, 3), :dig)
    sequence
  end

  def login
    Rosegold::Clientbound::Login.new(
      7, false, ["minecraft:overworld"], 20_u32, 10_u32, 10_u32,
      false, true, false, 0_u32, "minecraft:overworld", 0_i64, 0_u8,
      -1_i8, false, false, false, nil, nil, 0_u32, 63_u32, false
    )
  end

  def respawn(name = "minecraft:overworld", dimension_type = 0_u32)
    Rosegold::Clientbound::Respawn.new(
      dimension_type, name, 0_i64, 0_u8, -1_i8,
      false, false, false, nil, nil, 0_u32, 63_u32, 0_u8
    )
  end

  it "clears pending operations on login without rewinding the sequence" do
    sequence = track_operation(client)
    login.callback(client)
    expect(client.pending_block_operations).to be_empty
    expect(client.next_sequence).to be > sequence
  end

  it "drops the old dimension's mining prediction on login" do
    old_dimension = client.dimension_for_test
    data = Minecraft::IO::Memory.new
    (old_dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    old_dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), old_dimension))
    stone = Rosegold::MCData.default.block_state_names.index!("stone").to_u16
    old_dimension.set_block_state(0, 0, 0, stone)
    sequence = track_operation(client)

    expect(old_dimension.predict_block_break(Rosegold::Vec3i.new(0, 0, 0), sequence)).to be_true
    expect(old_dimension.mining_block_state(0, 0, 0)).not_to eq(stone)

    login.callback(client)

    expect(old_dimension.mining_block_state(0, 0, 0)).to eq(stone)
  end

  it "clears pending operations on respawn" do
    track_operation(client)
    respawn.callback(client)
    expect(client.pending_block_operations).to be_empty
  end

  it "starts with a fresh border on login even when the world key is unchanged" do
    old_border = client.dimension_for_test.world_border
    point = Rosegold::Vec3i.new(5, 0, 0)
    Rosegold::Clientbound::SetBorderSize.new(2.0).callback(client)
    expect(old_border.outside?(point)).to be_true

    login.callback(client)

    border = client.dimension_for_test.world_border
    expect(border.same?(old_border)).to be_false
    expect(border.outside?(point)).to be_false
  end

  it "retains only the border across same-world respawns without a registry" do
    world_key = "example:first"
    respawn(world_key).callback(client)
    old_world = client.dimension_for_test
    expect(old_world.name).to eq(world_key)
    expect({old_world.min_y, old_world.world_height}).to eq({-64, 384})
    data = Minecraft::IO::Memory.new
    (old_world.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    old_world.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), old_world))
    old_world.world_age = 12_i64
    old_world.time_of_day = 34_i64
    point = Rosegold::Vec3i.new(5, 0, 0)
    Rosegold::Clientbound::SetBorderSize.new(2.0).callback(client)

    respawn(world_key, 1_u32).callback(client)

    same_world = client.dimension_for_test
    expect(same_world.name).to eq(world_key)
    expect(same_world.chunks).to be_empty
    expect({same_world.world_age, same_world.time_of_day}).to eq({0_i64, 6_000_i64})
    expect(same_world.world_border.same?(old_world.world_border)).to be_true
    expect(same_world.world_border.outside?(point)).to be_true

    other_key = "example:second"
    respawn(other_key, 1_u32).callback(client)

    other_world = client.dimension_for_test
    expect(other_world.name).to eq(other_key)
    expect(other_world.world_border.same?(same_world.world_border)).to be_false
    expect(other_world.world_border.outside?(point)).to be_false
  end

  def register_border_scales(client, *scales : Minecraft::NBT::Tag?)
    registry = Rosegold::Dimension::REGISTRY_ID
    entries = scales.to_a.map_with_index do |scale, index|
      nbt = Minecraft::NBT::CompoundTag.new
      nbt["coordinate_scale"] = scale if scale
      io = Minecraft::IO::Memory.new
      io.write_byte(nbt.tag_type)
      nbt.write(io)
      {id: "example:dimension_#{index}", data: io.to_slice.as(Bytes?)}
    end
    client.registries[registry] = Rosegold::Clientbound::RegistryData.new(registry, entries)
  end

  sample [772_u32, 773_u32] do |protocol|
    it "scales only the 1.21.8 border center using the dimension type from login" do
      Rosegold::Client.protocol_version = protocol
      register_border_scales(client, Minecraft::NBT::DoubleTag.new(8.0))
      login.callback(client)
      Rosegold::Clientbound::InitializeBorder.new(80.0, -80.0, 8.0, 8.0, 0_i64, 100, 5, 15).callback(client)

      border = client.dimension_for_test.world_border
      expect(border.outside?(Rosegold::Vec3i.new(13, 0, -7))).to eq(protocol != 772_u32)
      expect(border.outside?(Rosegold::Vec3i.new(83, 0, -77))).to eq(protocol == 772_u32)
    ensure
      Rosegold::Client.reset_protocol_version!
    end
  end

  it "keeps the 1.21.8 center scale for the same world and reads it anew for another world" do
    Rosegold::Client.protocol_version = 772_u32
    register_border_scales(client, Minecraft::NBT::DoubleTag.new(8.0), Minecraft::NBT::DoubleTag.new(2.0))
    login.callback(client)
    Rosegold::Clientbound::SetBorderCenter.new(80.0, -80.0).callback(client)
    Rosegold::Clientbound::SetBorderSize.new(8.0).callback(client)
    scaled_point = Rosegold::Vec3i.new(10, 0, -10)

    respawn("minecraft:overworld", 1_u32).callback(client)
    expect(client.dimension_for_test.world_border.outside?(scaled_point)).to be_false

    respawn("example:second", 1_u32).callback(client)
    Rosegold::Clientbound::SetBorderCenter.new(80.0, -80.0).callback(client)
    Rosegold::Clientbound::SetBorderSize.new(8.0).callback(client)
    border = client.dimension_for_test.world_border
    expect(border.outside?(scaled_point)).to be_true
    expect(border.outside?(Rosegold::Vec3i.new(40, 0, -40))).to be_false
  ensure
    Rosegold::Client.reset_protocol_version!
  end

  it "accepts non-double 1.21.8 scales including both codec limits" do
    Rosegold::Client.protocol_version = 772_u32
    cases = {
      {Minecraft::NBT::ByteTag.new(8_u8), 8.0},
      {Minecraft::NBT::ShortTag.new(8_i16), 8.0},
      {Minecraft::NBT::IntTag.new(8_i32), 8.0},
      {Minecraft::NBT::LongTag.new(30_000_000_i64), 30_000_000.0},
      {Minecraft::NBT::FloatTag.new(1e-5_f32), 1e-5_f32.to_f64},
    }
    register_border_scales(client, *cases.map(&.first))
    cases.each_with_index do |(_, scale), index|
      respawn("example:scale_#{index}", index.to_u32).callback(client)
      Rosegold::Clientbound::InitializeBorder.new(10 * scale, -10 * scale, 8.0, 8.0, 0_i64, 100, 5, 15).callback(client)
      border = client.dimension_for_test.world_border
      expect(border.outside?(Rosegold::Vec3i.new(10, 0, -10))).to be_false
      expect(border.outside?(Rosegold::Vec3i.new(20, 0, -20))).to be_true
    end
  ensure
    Rosegold::Client.reset_protocol_version!
  end

  it "does not reject with unknown 1.21.8 scale unless the center is zero" do
    Rosegold::Client.protocol_version = 772_u32
    scales = [nil, Minecraft::NBT::StringTag.new("8"), Minecraft::NBT::ByteTag.new(0xff_u8)] of Minecraft::NBT::Tag?
    [0.0, -8.0, 1e-6, 30_000_001.0, Float64::INFINITY, Float64::NAN].each { |scale| scales << Minecraft::NBT::DoubleTag.new(scale) }
    scales.each do |scale|
      register_border_scales(client, scale)
      respawn("minecraft:the_nether").callback(client)
      Rosegold::Clientbound::InitializeBorder.new(80.0, -80.0, 8.0, 8.0, 0_i64, 100, 5, 15).callback(client)
      border = client.dimension_for_test.world_border
      point = Rosegold::Vec3i.new(10, 0, -10)
      expect(border.outside?(point)).to be_false

      Rosegold::Clientbound::SetBorderCenter.new(0.0, 0.0).callback(client)
      expect(border.outside?(point)).to be_true
      respawn("minecraft:overworld").callback(client)
    end
  ensure
    Rosegold::Client.reset_protocol_version!
  end

  it "clears pending operations when PLAY moves to CONFIGURATION" do
    track_operation(client)
    client.leave_play
    expect(client.pending_block_operations).to be_empty
  end

  it "clears active item use with the mining session" do
    client.player.using_item = true
    respawn.callback(client)
    expect(client.player.using_item?).to be_false
  end

  it "drops a held use, its prediction and its tap sequence when PLAY ends" do
    inputs = client.interactions_for_test
    apple = Rosegold::MCData.default.items.find! { |item| item.name == "apple" }
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, apple.id)
    inputs.tap_using_hand
    inputs.tick
    sequence = inputs.last_hand_tap_sequence
    expect(sequence).to be > 0

    inputs.start_using_hand
    client.sent_packets.clear
    client.leave_play
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    inputs.tick

    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty
    expect(client.sent_packets.select(Rosegold::Serverbound::UseItem)).to be_empty
    expect(inputs.last_hand_tap_sequence).to eq(0)
    expect(client.pending_block_operations).to be_empty
    expect(client.next_sequence).to eq(sequence + 1)
  end

  it "cleans up when the active connection closes" do
    track_operation(client)
    client.resume_physics
    client.player.using_item = true
    client.connection.disconnect("closed")
    expect(client.pending_block_operations).to be_empty
    expect(client.player.using_item?).to be_false
    expect(client.physics_paused?).to be_true
  end

  it "ignores a late disconnect from a replaced connection" do
    old = client.replace_connection
    track_operation(client)
    client.resume_physics
    old.disconnect("old transport closed")
    client.emit_event Rosegold::Event::Disconnected.new(Rosegold::TextComponent.new("late"))
    expect(client.pending_block_operations.size).to eq(1)
    expect(client.physics_paused?).to be_false
  end

  it "keeps pending operations on other state changes" do
    client.set_protocol_state(Rosegold::ProtocolState::CONFIGURATION)
    track_operation(client)
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    expect(client.pending_block_operations.size).to eq(1)
  end
end
