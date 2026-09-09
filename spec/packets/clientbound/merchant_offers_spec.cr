require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::MerchantOffers do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::MerchantOffers[772_u32]).to eq(0x2D_u32)
  end

  it "uses correct packet ID for protocol 773" do
    expect(Rosegold::Clientbound::MerchantOffers[773_u32]).to eq(0x32_u32)
  end

  it "uses correct packet ID for protocol 774" do
    expect(Rosegold::Clientbound::MerchantOffers[774_u32]).to eq(0x32_u32)
  end

  it "uses correct packet ID for protocol 775" do
    expect(Rosegold::Clientbound::MerchantOffers[775_u32]).to eq(0x34_u32)
  end

  it "uses correct packet ID for protocol 776" do
    expect(Rosegold::Clientbound::MerchantOffers[776_u32]).to eq(0x34_u32)
  end

  it "supports all five protocols" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      expect(Rosegold::Clientbound::MerchantOffers.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::MerchantOffers.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::MerchantOffers.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x2D_u8, 772_u32)).to eq(Rosegold::Clientbound::MerchantOffers)
  end

  describe "packet parsing" do
    it "parses every field of a two-offer fixture" do
      Rosegold::Client.protocol_version = 772_u32
      max_stack_size_id = Rosegold::DataComponentTypes.id_for("max_stack_size", 772_u32) || raise "max_stack_size component id missing"

      io = Minecraft::IO::Memory.new
      io.write 5_u32 # container_id
      io.write 2_u32 # trade count

      # Offer 1: base_cost_a carries a component, cost_b present.
      io.write 10_u32 # base_cost_a item_id
      io.write 2_u32  # base_cost_a count
      io.write 1_u32  # base_cost_a component count
      io.write max_stack_size_id
      io.write 64_u32        # MaxStackSize payload
      io.write 1_u32         # result count
      io.write 20_u32        # result item_id
      io.write 0_u32         # result components_to_add
      io.write 0_u32         # result components_to_remove
      io.write true          # cost_b present
      io.write 30_u32        # cost_b item_id
      io.write 1_u32         # cost_b count
      io.write 0_u32         # cost_b component count
      io.write false         # out_of_stock
      io.write_full 3_i32    # uses
      io.write_full 12_i32   # max_uses
      io.write_full 5_i32    # xp
      io.write_full(-1_i32)  # special_price_diff
      io.write_full 0.05_f32 # price_multiplier
      io.write_full 0_i32    # demand

      # Offer 2: bare base cost, no cost_b, no components.
      io.write 40_u32 # base_cost_a item_id
      io.write 1_u32  # base_cost_a count
      io.write 0_u32  # base_cost_a component count
      io.write 1_u32  # result count
      io.write 50_u32 # result item_id
      io.write 0_u32
      io.write 0_u32
      io.write false      # cost_b absent
      io.write true       # out_of_stock
      io.write_full 0_i32 # uses
      io.write_full 7_i32 # max_uses
      io.write_full 2_i32 # xp
      io.write_full 0_i32 # special_price_diff
      io.write_full 1.0_f32
      io.write_full 4_i32 # demand

      io.write 3_u32   # villager_level
      io.write 150_u32 # villager_xp
      io.write true    # show_progress
      io.write false   # can_restock
      io.pos = 0

      packet = Rosegold::Clientbound::MerchantOffers.read(io)

      expect(packet.container_id).to eq(5_u32)
      expect(packet.trades.size).to eq(2)
      expect(packet.villager_level).to eq(3_u32)
      expect(packet.villager_xp).to eq(150_u32)
      expect(packet.show_progress?).to be_true
      expect(packet.can_restock?).to be_false

      first = packet.trades[0]
      expect(first.base_cost_a.item_id).to eq(10_u32)
      expect(first.base_cost_a.count).to eq(2_u32)
      expect(first.base_cost_a.components.size).to eq(1)
      component_type, component = first.base_cost_a.components[0]
      expect(component_type).to eq(max_stack_size_id)
      expect(component).to be_a(Rosegold::DataComponents::MaxStackSize)
      expect(component.as(Rosegold::DataComponents::MaxStackSize).value).to eq(64_u32)
      expect(first.result.item_id_int).to eq(20_u32)
      expect(first.cost_b).not_to be_nil
      expect(first.cost_b.try &.item_id).to eq(30_u32)
      expect(first.out_of_stock?).to be_false
      expect(first.uses).to eq(3)
      expect(first.max_uses).to eq(12)
      expect(first.xp).to eq(5)
      expect(first.special_price_diff).to eq(-1)
      expect(first.price_multiplier).to eq(0.05_f32)
      expect(first.demand).to eq(0)

      second = packet.trades[1]
      expect(second.base_cost_a.item_id).to eq(40_u32)
      expect(second.base_cost_a.components.size).to eq(0)
      expect(second.cost_b).to be_nil
      expect(second.out_of_stock?).to be_true
      expect(second.max_uses).to eq(7)
      expect(second.demand).to eq(4)
    end
  end

  describe "round-trip serialization" do
    it "preserves every field including a component-bearing ItemCost" do
      Rosegold::Client.protocol_version = 772_u32
      max_stack_size_id = Rosegold::DataComponentTypes.id_for("max_stack_size", 772_u32) || raise "max_stack_size component id missing"

      base_cost_a = Rosegold::Clientbound::MerchantOffers::ItemCost.new(
        10_u32, 2_u32, [{max_stack_size_id, Rosegold::DataComponents::MaxStackSize.new(64_u32).as(Rosegold::DataComponent)}])
      cost_b = Rosegold::Clientbound::MerchantOffers::ItemCost.new(30_u32, 1_u32)
      offer1 = Rosegold::Clientbound::MerchantOffers::MerchantOffer.new(
        base_cost_a, Rosegold::Slot.new(1_u32, 20_u32), cost_b, false,
        3, 12, 5, -1, 0.05_f32, 0)
      offer2 = Rosegold::Clientbound::MerchantOffers::MerchantOffer.new(
        Rosegold::Clientbound::MerchantOffers::ItemCost.new(40_u32, 1_u32),
        Rosegold::Slot.new(1_u32, 50_u32), nil, true,
        0, 7, 2, 0, 1.0_f32, 4)

      original = Rosegold::Clientbound::MerchantOffers.new(5_u32, [offer1, offer2], 3_u32, 150_u32, true, false)

      io = Minecraft::IO::Memory.new(original.write)
      io.read_byte # skip packet ID

      read = Rosegold::Clientbound::MerchantOffers.read(io)

      expect(read.container_id).to eq(5_u32)
      expect(read.trades.size).to eq(2)
      expect(read.trades[0].base_cost_a.components.size).to eq(1)
      expect(read.trades[0].base_cost_a.components[0][0]).to eq(max_stack_size_id)
      expect(read.trades[0].cost_b.try &.item_id).to eq(30_u32)
      expect(read.trades[0].price_multiplier).to eq(0.05_f32)
      expect(read.trades[0].special_price_diff).to eq(-1)
      expect(read.trades[1].cost_b).to be_nil
      expect(read.trades[1].out_of_stock?).to be_true
      expect(read.villager_xp).to eq(150_u32)
      expect(read.show_progress?).to be_true
    end
  end

  describe "callback behavior" do
    let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

    it "stores offers and metadata on a matching MerchantMenu" do
      menu = Rosegold::MerchantMenu.new(client, 7_u8, Rosegold::Chat.new("Trader"))
      client.container_menu = menu

      offer = Rosegold::Clientbound::MerchantOffers::MerchantOffer.new(
        Rosegold::Clientbound::MerchantOffers::ItemCost.new(1_u32, 1_u32),
        Rosegold::Slot.new(1_u32, 2_u32), nil, false, 0, 5, 1, 0, 1.0_f32, 0)
      packet = Rosegold::Clientbound::MerchantOffers.new(7_u32, [offer], 2_u32, 40_u32, true, true)

      packet.callback(client)

      expect(menu.trades.size).to eq(1)
      expect(menu.villager_level).to eq(2_u32)
      expect(menu.villager_xp).to eq(40_u32)
      expect(menu.show_progress?).to be_true
      expect(menu.can_restock?).to be_true
    end

    it "ignores offers when the container id does not match" do
      menu = Rosegold::MerchantMenu.new(client, 7_u8, Rosegold::Chat.new("Trader"))
      client.container_menu = menu

      offer = Rosegold::Clientbound::MerchantOffers::MerchantOffer.new(
        Rosegold::Clientbound::MerchantOffers::ItemCost.new(1_u32, 1_u32),
        Rosegold::Slot.new(1_u32, 2_u32), nil, false, 0, 5, 1, 0, 1.0_f32, 0)
      packet = Rosegold::Clientbound::MerchantOffers.new(99_u32, [offer], 2_u32, 40_u32, true, true)

      packet.callback(client)

      expect(menu.trades.size).to eq(0)
    end
  end
end
