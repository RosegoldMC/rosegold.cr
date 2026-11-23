require "../spec_helper"

class InteractionUseRoutingSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet
  getter placement_states = [] of UInt16?
  getter placement_above_states = [] of UInt16?

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
    if packet.is_a?(Rosegold::Serverbound::PlayerBlockPlacement)
      placement_states << dimension.interaction_block_state(packet.location)
      placement_above_states << dimension.interaction_block_state(packet.location.up)
    end
  end

  def use_input
    interactions
  end
end

Spectator.describe "Interaction use routing" do
  let(bot_client) { InteractionUseRoutingSpecClient.new("localhost") }
  let(dimension) { bot_client.dimension_for_test }
  let(input) { bot_client.use_input }
  let(player) { bot_client.player }
  let(packets) { bot_client.sent_packets }
  let(swings) { [] of Rosegold::Event::ArmSwing }
  let(target) { Rosegold::Vec3i.new(2, 0, 2) }

  before_each do
    Rosegold::Client.protocol_version = Rosegold::Client::LATEST_PROTOCOL
    data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension))
    aim
    bot_client.on(Rosegold::Event::ArmSwing) { |event| swings << event }
    input.tick
    packets.clear
  end

  after_each { Rosegold::Client.reset_protocol_version! }

  def aim(x = 2.5, y = 0.5, z = 0.5)
    eye_height = player.sneaking? ? Rosegold::Player::SNEAKING_EYE_HEIGHT : Rosegold::Player::DEFAULT_EYE_HEIGHT
    player.feet = Rosegold::Vec3d.new(x, y - eye_height, z)
    player.look = Rosegold::Look::SOUTH
  end

  def state(name : String, *properties)
    mc = Rosegold::MCData.default
    block = mc.blocks.find! { |entry| entry.id_str == name }
    (block.min_state_id..block.max_state_id).find! do |id|
      properties.all? { |property| mc.block_state_names[id].includes?(property) }
    end
  end

  def hold(name : String, hand = Rosegold::Hand::MainHand)
    item = Rosegold::MCData.default.items.find! { |entry| entry.name == name }
    bot_client.inventory_menu[hand.main_hand? ? 36 : 45] = Rosegold::Slot.new(1_u32, item.id)
  end

  def tap(hand : Rosegold::Hand? = Rosegold::Hand::MainHand)
    input.tap_using_hand(hand)
    input.tick
  end

  def wire
    packets.map do |packet|
      case packet
      when Rosegold::Serverbound::PlayerBlockPlacement then {"on", packet.hand, packet.sequence}
      when Rosegold::Serverbound::UseItem              then {"use", packet.hand, packet.sequence}
      when Rosegold::Serverbound::InteractEntity       then {"entity", packet.hand, 0}
      when Rosegold::Serverbound::SwingArm             then {"swing", packet.hand, 0}
      when Rosegold::Serverbound::PlayerAction         then {"action", Rosegold::Hand::MainHand, packet.sequence}
      else                                                  {packet.class.to_s, Rosegold::Hand::MainHand, 0}
      end
    end
  end

  let(main) { Rosegold::Hand::MainHand }
  let(off) { Rosegold::Hand::OffHand }

  def spawn_target(name : String)
    type = Rosegold::Entity.metadata_for_protocol.find! { |entry| entry.name == name }.id.to_u32
    entity = Rosegold::Entity.new(81_u32, UUID.random, type, Rosegold::Vec3d.new(2.375, 0.0, 2.0),
      0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
    dimension.entities[entity.entity_id.to_u64] = entity
    entity
  end

  def placement
    packets.first.as(Rosegold::Serverbound::PlayerBlockPlacement)
  end

  sample Rosegold::Client::SUPPORTED_PROTOCOLS do |protocol|
    it "predicts button success before sending use and swings only once" do
      Rosegold::Client.protocol_version = protocol
      before = state("stone_button", "face=wall", "facing=north", "powered=false")
      after = state("stone_button", "face=wall", "facing=north", "powered=true")
      dimension.set_block_state(target, before)
      hold("apple")

      tap

      expect(packets.map(&.class)).to eq(protocol < 777 ? [Rosegold::Serverbound::PlayerBlockPlacement, Rosegold::Serverbound::SwingArm] : [Rosegold::Serverbound::PlayerBlockPlacement])
      expect(placement.location).to eq(target)
      expect(placement.hand).to eq(Rosegold::Hand::MainHand)
      expect(placement.sequence).to eq(1)
      expect(input.last_hand_tap_sequence).to eq(placement.sequence)
      expect(bot_client.pending_block_operations[placement.sequence].operation_type).to eq(:place)
      expect(swings.map(&.hand)).to eq([Rosegold::Hand::MainHand])
      expect(bot_client.placement_states).to eq([after])
      expect(dimension.block_state(target)).to eq(before)
      expect(dimension.interaction_block_state(target)).to eq(after)

      Rosegold::Clientbound::AcknowledgeBlockChange.new(placement.sequence).callback(bot_client)

      expect(bot_client.pending_block_operations).to be_empty
      expect(dimension.block_state(target)).to eq(before)
      expect(dimension.interaction_block_state(target)).to eq(before)
    end

    it "predicts both door halves before the packet and keeps the latest toggle until its acknowledgement" do
      Rosegold::Client.protocol_version = protocol
      lower_closed = state("oak_door", "facing=north", "half=lower", "hinge=left", "open=false", "powered=false")
      upper_closed = state("oak_door", "facing=north", "half=upper", "hinge=left", "open=false", "powered=false")
      lower_open = state("oak_door", "facing=north", "half=lower", "hinge=left", "open=true", "powered=false")
      upper_open = state("oak_door", "facing=north", "half=upper", "hinge=left", "open=true", "powered=false")
      dimension.set_block_state(target, lower_closed)
      dimension.set_block_state(target.up, upper_closed)
      hold("apple", off)
      aim(x: 2.125)

      tap(nil)

      swing = protocol < 777 ? [{"swing", main, 0}] : [] of {String, Rosegold::Hand, Int32}
      expect(wire).to eq([{"on", main, 1}] + swing)
      expect(swings.map(&.hand)).to eq([main])
      expect(bot_client.placement_states).to eq([lower_open])
      expect(bot_client.placement_above_states).to eq([upper_open])
      expect(dimension.block_state(target)).to eq(lower_closed)
      expect(dimension.block_state(target.up)).to eq(upper_closed)
      opened = placement.sequence

      packets.clear
      aim(x: 2.125, y: 1.5)
      tap(nil)

      closed = placement.sequence
      expect(wire).to eq([{"on", main, 2}] + swing)
      expect(placement.location).to eq(target.up)
      expect(swings.map(&.hand)).to eq([main, main])
      expect(dimension.interaction_block_state(target)).to eq(lower_closed)
      expect(dimension.interaction_block_state(target.up)).to eq(upper_closed)

      Rosegold::Clientbound::BlockChange.new(target, lower_open).callback(bot_client)
      Rosegold::Clientbound::BlockChange.new(target.up, upper_open).callback(bot_client)
      Rosegold::Clientbound::AcknowledgeBlockChange.new(opened).callback(bot_client)
      expect(bot_client.pending_block_operations.keys).to eq([closed])
      expect(dimension.block_state(target)).to eq(lower_open)
      expect(dimension.block_state(target.up)).to eq(upper_open)
      expect(dimension.interaction_block_state(target)).to eq(lower_closed)
      expect(dimension.interaction_block_state(target.up)).to eq(upper_closed)

      Rosegold::Clientbound::AcknowledgeBlockChange.new(closed).callback(bot_client)
      expect(bot_client.pending_block_operations).to be_empty
      expect(dimension.interaction_block_state(target)).to eq(lower_open)
      expect(dimension.interaction_block_state(target.up)).to eq(upper_open)
    end

    it "sends a relative entity hit with the selected hand and sneaking flag" do
      Rosegold::Client.protocol_version = protocol
      entity = spawn_target("villager")
      player.sneaking = true
      aim
      hold("apple", Rosegold::Hand::OffHand)

      tap(Rosegold::Hand::OffHand)

      entity_id = entity.entity_id.to_u64
      expected_classes = Array(Rosegold::Serverbound::Packet.class).new(protocol < 775 ? 2 : 1, Rosegold::Serverbound::InteractEntity)
      expected_classes << Rosegold::Serverbound::SwingArm if protocol < 777
      expect(packets.map(&.class)).to eq(expected_classes)
      expected = Rosegold::Serverbound::InteractEntity.new(entity_id, :interact_at, 0.125_f32, 0.5_f32,
        (entity.bounding_box.min.z - entity.position.z).to_f32, :off_hand, true)
      expect(packets.first.as(Rosegold::Serverbound::InteractEntity).write).to eq(expected.write)
      if protocol < 775
        fallback = Rosegold::Serverbound::InteractEntity.new(entity_id, :interact, hand: :off_hand, sneaking: true)
        expect(packets[1].as(Rosegold::Serverbound::InteractEntity).write).to eq(fallback.write)
      end
      expect(packets.last.as(Rosegold::Serverbound::SwingArm).hand).to eq(Rosegold::Hand::OffHand) if protocol < 777
      expect(swings.map(&.hand)).to eq([Rosegold::Hand::OffHand])
      expect(bot_client.pending_block_operations).to be_empty
    end

    it "keeps the legacy use swing for an unknown block result and never sends Punch for it" do
      Rosegold::Client.protocol_version = protocol
      note = state("note_block")
      dimension.set_block_state(target, note)
      hold("stick")

      tap

      expected = [Rosegold::Serverbound::PlayerBlockPlacement] of Rosegold::Serverbound::Packet.class
      expected << Rosegold::Serverbound::SwingArm if protocol < 777
      expect(packets.map(&.class)).to eq(expected)
      expect(packets.none?(Rosegold::Serverbound::Punch)).to be_true
      expect(bot_client.placement_states).to eq([note])
      expect(dimension.interaction_block_state(target)).to eq(note)
      expect(swings.map(&.hand)).to eq([Rosegold::Hand::MainHand])
    end

    it "does not swing for a spectator's entity use" do
      Rosegold::Client.protocol_version = protocol
      spawn_target("villager")
      player.gamemode = 3_i8
      hold("apple")

      tap

      expect(packets.all?(Rosegold::Serverbound::InteractEntity)).to be_true
      expect(packets).to_not be_empty
      expect(swings).to be_empty
    end
  end

  sample Rosegold::Client::SUPPORTED_PROTOCOLS do |protocol|
    it "automatically uses the block with both hands, then the offhand item, after an empty main hand passes" do
      Rosegold::Client.protocol_version = protocol
      dimension.set_block_state(target, state("stone"))
      hold("apple", off)

      tap(nil)

      expect(wire).to eq([{"on", main, 1}, {"on", off, 2}, {"use", off, 3}])
      expect(input.last_hand_tap_sequence).to eq(3)
      expect(bot_client.pending_block_operations.values.map(&.operation_type)).to eq([:place, :place, :use])
      expect(swings).to be_empty

      input.tick
      expect(wire.last).to eq({"action", main, 0})
      expect(input.last_hand_tap_sequence).to eq(3)
    end

    it "automatically stops after a main-hand block success or an unproven entity result" do
      Rosegold::Client.protocol_version = protocol
      dimension.set_block_state(target, state("stone_button", "face=wall", "facing=north", "powered=false"))
      hold("apple", off)

      tap(nil)

      swing = protocol < 777 ? [{"swing", main, 0}] : [] of {String, Rosegold::Hand, Int32}
      expect(wire).to eq([{"on", main, 1}] + swing)

      4.times { input.tick }
      packets.clear
      spawn_target("cow")
      tap(nil)

      entity = Array.new(protocol < 775 ? 2 : 1, {"entity", main, 0})
      expect(wire).to eq(entity + swing)
    end

    it "automatically interacts with the same entity using the offhand after an empty main hand passes" do
      Rosegold::Client.protocol_version = protocol
      spawn_target("player")
      hold("apple", off)

      tap(nil)

      interactions = protocol < 775 ? 2 : 1
      main_entity = Array.new(interactions, {"entity", main, 0})
      off_entity = Array.new(interactions, {"entity", off, 0})
      expect(wire).to eq(main_entity + off_entity + [{"use", off, 1}])
      expect(packets.select(Rosegold::Serverbound::InteractEntity).map(&.entity_id).uniq!).to eq([81_u64])
      expect(input.last_hand_tap_sequence).to eq(1)
      expect(swings).to be_empty
    end

    it "interacts with an entity in both hands for a spectator without item use or swing" do
      Rosegold::Client.protocol_version = protocol
      spawn_target("villager")
      player.gamemode = 3_i8
      hold("apple")
      hold("apple", off)

      tap(nil)

      interactions = protocol < 775 ? 2 : 1
      off_entity = Array.new(interactions, {"entity", off, 0})
      expect(wire).to eq(Array.new(interactions, {"entity", main, 0}) + off_entity)
      expect(swings).to be_empty
      expect(bot_client.pending_block_operations).to be_empty
    end
  end

  it "advances an automatic miss past an empty main hand without sending it" do
    hold("apple", off)

    tap(nil)

    expect(wire).to eq([{"use", off, 1}])
    expect(input.last_hand_tap_sequence).to eq(1)
  end

  it "advances an automatic miss after a passing main item and stops after the offhand consumes" do
    hold("stone")
    hold("apple", off)

    tap(nil)
    expect(wire).to eq([{"use", main, 1}, {"use", off, 2}])
    expect(input.last_hand_tap_sequence).to eq(2)

    input.tick
    expect(wire.last).to eq({"action", main, 0})
    packets.clear
    hold("apple")
    hold("stone", off)
    tap(nil)
    expect(wire).to eq([{"use", main, 3}])
  end

  it "advances after a known generic failure that follows a block pass" do
    dimension.set_block_state(target, state("stone"))
    player.food = 20
    hold("apple")
    hold("apple", off)

    tap(nil)

    expect(wire).to eq([{"on", main, 1}, {"use", main, 2}, {"on", off, 3}, {"use", off, 4}])
    expect(input.last_hand_tap_sequence).to eq(4)
  end

  it "does not try the offhand after a known block fail, a consume, or an unknown block result" do
    hold("apple", off)
    cases = {
      {"cobblestone", state("stone"), 0.875, ["on"], 0},
      {"apple", state("stone_button", "face=wall", "facing=north", "powered=true"), 0.5, ["on"], 0},
      {"flint_and_steel", state("stone"), 0.5, ["on", "use"], 1},
      {"flint_and_steel", state("note_block"), 0.5, ["on"], 1},
    }
    cases.each do |item, block, eye_z, expected, swing_count|
      dimension.set_block_state(target, block)
      aim(z: eye_z)
      hold(item)
      4.times { input.tick }
      packets.clear
      swings.clear

      tap(nil)

      expect(wire.map { |kind, hand, _| {kind, hand} }).to eq(expected.map { |kind| {kind, main} })
      expect(swings.map(&.hand)).to eq(Array.new(swing_count, main))
    end
  end

  it "falls through an unregistered offhand item on a cauldron after an empty main hand passes" do
    dimension.set_block_state(target, state("cauldron"))
    bot_client.inventory_menu[45] = Rosegold::Slot.new(1_u32, 999_999_u32)

    tap(nil)

    expect(wire).to eq([{"on", main, 1}, {"on", off, 2}, {"use", off, 3}])
    expect(swings.map(&.hand)).to eq([off])
  end

  it "keeps explicit hands single for a pass" do
    dimension.set_block_state(target, state("stone"))
    hold("apple", off)

    tap(main)
    expect(wire).to eq([{"on", main, 1}])
  end

  sample Rosegold::Client::SUPPORTED_PROTOCOLS.select { |protocol| protocol < 775_u32 } do |protocol|
    it "sends legacy Interact for armor stands only when InteractAt passes" do
      Rosegold::Client.protocol_version = protocol
      interact_at = Rosegold::Serverbound::InteractEntity::Action::InteractAt
      interact = Rosegold::Serverbound::InteractEntity::Action::Interact

      spawn_target("armor_stand")

      tap

      actions = packets.select(Rosegold::Serverbound::InteractEntity).map(&.action)
      expect(actions).to eq([interact_at])
      expect(wire).to eq([{"entity", main, 0}])
      expect(swings).to be_empty

      4.times { input.tick }
      packets.clear
      swings.clear
      hold("name_tag")
      tap

      actions = packets.select(Rosegold::Serverbound::InteractEntity).map(&.action)
      expect(actions).to eq([interact_at, interact])
      expect(wire).to eq([{"entity", main, 0}, {"entity", main, 0}, {"use", main, 1}])
      expect(swings).to be_empty
    end
  end

  it "passes from a plain block without using the empty selected hand" do
    stone = state("stone")
    dimension.set_block_state(target, stone)
    hold("apple")

    tap(Rosegold::Hand::OffHand)
    input.tick

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(placement.hand).to eq(Rosegold::Hand::OffHand)
    expect(placement.location).to eq(target)
    expect(placement.face).to eq(BlockFace::North)
    expect(placement.cursor).to eq(Rosegold::Vec3f.new(0.5, 0.5, 0.0))
    expect(swings).to be_empty
  end

  it "does not swing or use again when placement would intersect the player" do
    dimension.set_block_state(target, state("stone"))
    aim(z: 0.875)
    hold("cobblestone")

    tap
    input.tick

    air = state("air")
    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(dimension.interaction_block_state(Rosegold::Vec3i.new(2, 0, 1))).to eq(air)
    expect(swings).to be_empty
  end

  it "does not swing, eat, or release when a powered button consumes use" do
    powered = state("stone_button", "face=wall", "facing=north", "powered=true")
    dimension.set_block_state(target, powered)
    hold("apple")

    tap
    input.tick

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(bot_client.placement_states).to eq([powered])
    expect(swings).to be_empty
  end

  it "keeps the fallback to generic item use for a permissive unknown block result" do
    stone = state("stone")
    dimension.set_block_state(target, stone)
    hold("flint_and_steel")

    tap

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement, Rosegold::Serverbound::UseItem])
    expect(packets.last.as(Rosegold::Serverbound::UseItem).sequence).to eq(placement.sequence + 1)
    expect(input.last_hand_tap_sequence).to eq(placement.sequence + 1)
    expect(bot_client.placement_states).to eq([stone])
    expect(swings.map(&.hand)).to eq([Rosegold::Hand::MainHand])
  end

  it "starts sustained use after a permissive unknown block result" do
    dimension.set_block_state(target, state("stone"))
    hold("stick")
    custom = bot_client.inventory_menu[36]
    custom.components_to_add["food"] = Rosegold::DataComponents::Food.new
    custom.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new
    bot_client.inventory_menu[36] = custom
    hold("shield", off)

    tap(nil)

    expect(wire).to eq([{"on", main, 1}, {"use", main, 2}])
    expect(swings.map(&.hand)).to eq([main])
    input.tick
    expect(wire).to eq([{"on", main, 1}, {"use", main, 2}, {"action", main, 0}])
    expect(packets.last.as(Rosegold::Serverbound::PlayerAction).status).to eq(Rosegold::Serverbound::PlayerAction::Status::FinishUsingHand)
  end

  it "keeps an unknown block's old suppression and its legacy swing" do
    note = state("note_block")
    dimension.set_block_state(target, note)
    hold("apple")

    tap
    input.tick

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(bot_client.placement_states).to eq([note])
    expect(swings.map(&.hand)).to eq([Rosegold::Hand::MainHand])
  end

  it "uses a plain offhand apple after blocks whose own use needs the main hand" do
    hold("apple", Rosegold::Hand::OffHand)
    blocks = {
      {state("stone_button", "face=wall", "facing=north", "powered=false"), 0.5},
      {state("oak_trapdoor", "facing=north", "half=bottom", "open=false", "waterlogged=false"), 0.1},
      {state("chest", "facing=north", "type=single", "waterlogged=false"), 0.5},
    }
    blocks.each do |block, eye_y|
      dimension.set_block_state(target, block)
      aim(y: eye_y)
      packets.clear
      bot_client.placement_states.clear

      tap(Rosegold::Hand::OffHand)

      expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement, Rosegold::Serverbound::UseItem])
      expect(placement.location).to eq(target)
      expect(placement.hand).to eq(Rosegold::Hand::OffHand)
      use = packets.last.as(Rosegold::Serverbound::UseItem)
      expect({use.hand, use.sequence}).to eq({Rosegold::Hand::OffHand, placement.sequence + 1})
      expect(bot_client.placement_states).to eq([block])
      expect(dimension.interaction_block_state(target)).to eq(block)
      expect(swings).to be_empty

      input.tick
      release = packets.last.as(Rosegold::Serverbound::PlayerAction)
      expect({release.status, release.sequence}).to eq({Rosegold::Serverbound::PlayerAction::Status::FinishUsingHand, 0})
    end
  end

  it "keeps an unproven offhand item on a main-hand block suppressed" do
    button = state("stone_button", "face=wall", "facing=north", "powered=false")
    dimension.set_block_state(target, button)
    hold("carrot", Rosegold::Hand::OffHand)

    tap(Rosegold::Hand::OffHand)

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(dimension.interaction_block_state(target)).to eq(button)
  end

  it "keeps sneak bypass for a normally consuming unknown block" do
    dimension.set_block_state(target, state("note_block"))
    hold("flint_and_steel")
    player.sneaking = true
    aim

    tap

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement, Rosegold::Serverbound::UseItem])
    expect(swings.map(&.hand)).to eq([Rosegold::Hand::MainHand])
  end

  it "does not use or release an empty hand with no target" do
    input.start_using_hand
    input.tick
    input.stop_using_hand
    input.tick

    expect(packets).to be_empty
    expect(swings).to be_empty
    expect(input.last_hand_tap_sequence).to eq(0)
  end

  it "skips generic spectator use but still sends targeted block use" do
    player.gamemode = 3_i8
    hold("apple")
    tap
    expect(packets).to be_empty

    dimension.set_block_state(target, state("stone"))
    4.times { input.tick }
    tap
    input.tick

    expect(packets.map(&.class)).to eq([Rosegold::Serverbound::PlayerBlockPlacement])
    expect(swings).to be_empty
  end

  it "uses the cached block hit after a same-tick instant break and reconciles both sequences" do
    torch = state("torch")
    stone = state("stone")
    air = state("air")
    dimension.set_block_state(target, torch)
    dimension.set_block_state(target.down, stone)
    hold("stone")

    input.start_digging
    tap

    swing_packet = Rosegold::Client.protocol_version >= 777 ? Rosegold::Serverbound::Punch : Rosegold::Serverbound::SwingArm
    expected = [Rosegold::Serverbound::PlayerAction, swing_packet, Rosegold::Serverbound::PlayerBlockPlacement]
    expected << Rosegold::Serverbound::SwingArm if Rosegold::Client.protocol_version < 777
    expect(packets.map(&.class)).to eq(expected)
    dig = packets[0].as(Rosegold::Serverbound::PlayerAction)
    use = packets[2].as(Rosegold::Serverbound::PlayerBlockPlacement)
    expect(dig.status).to eq(Rosegold::Serverbound::PlayerAction::Status::Start)
    expect(dig.location).to eq(target)
    expect(use.location).to eq(target)
    expect(use.sequence).to eq(dig.sequence + 1)
    expect(bot_client.placement_states).to eq([stone])
    expect(dimension.block_state(target)).to eq(torch)

    Rosegold::Clientbound::BlockChange.new(target, air).callback(bot_client)
    Rosegold::Clientbound::AcknowledgeBlockChange.new(dig.sequence).callback(bot_client)
    expect(dimension.block_state(target)).to eq(air)
    expect(dimension.interaction_block_state(target)).to eq(stone)

    Rosegold::Clientbound::AcknowledgeBlockChange.new(use.sequence).callback(bot_client)
    expect(dimension.block_state(target)).to eq(air)
    expect(dimension.interaction_block_state(target)).to eq(air)
  end
end
