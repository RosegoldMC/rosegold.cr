require "../spec_helper"

Spectator.describe "Minecraft 26.3 game data" do
  it "receives new items and block states from the vanilla server" do
    connection = client
    parse_failures = [] of UInt32
    connection.on(Rosegold::Clientbound::RawPacket) do |packet|
      if connection.current_protocol_state.get_clientbound_packet(packet.packet_id, connection.protocol_version)
        parse_failures << packet.packet_id
      end
    end

    connection.join_game do |connected|
      next unless connected.protocol_version == 777_u32

      bot = Rosegold::Bot.new(connected)
      admin.setup_arena
      admin.tp 0, -60, 0
      admin.clear
      admin.give "poplar_planks", 8
      admin.give "red_cushion", 1
      admin.setblock 2, -60, 0, "poplar_planks"

      deadline = Time.monotonic + 5.seconds
      until bot.inventory.count("poplar_planks") == 8 && bot.inventory.count("red_cushion") == 1 &&
            connected.dimension_for_test.block_state(2, -60, 0).try { |state| Rosegold::Block.from_block_state_id(state).id_str == "poplar_planks" }
        raise "26.3 items or blocks did not reach the client" if Time.monotonic >= deadline
        bot.wait_tick
      end

      expect(bot.inventory.pick("poplar_planks")).to be_true
      expect(bot.inventory.main_hand.name).to eq("poplar_planks")
      state = connected.dimension_for_test.block_state(2, -60, 0).as(UInt16)
      expect(Rosegold::MCData.default.block_state_collision_shapes[state]).not_to be_empty
      expect(parse_failures).to be_empty
    end
  end
end
