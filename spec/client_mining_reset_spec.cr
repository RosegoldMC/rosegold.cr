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

  def respawn
    Rosegold::Clientbound::Respawn.new(
      0_u32, "minecraft:overworld", 0_i64, 0_u8, -1_i8,
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
