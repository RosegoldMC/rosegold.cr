require "./spec_helper"

Spectator.describe Rosegold::Bot do
  {% for protocol in Rosegold::ENABLED_PROTOCOLS.keys %}
    context "riding on protocol {{protocol}}" do
      let(bot_client) { Rosegold::Client.new("localhost") }
      let(bot) { Rosegold::Bot.new(bot_client) }
      let(vehicle) do
        type = Rosegold::Entity.metadata_for_protocol.find! { |metadata| metadata.name == "minecart" }
        Rosegold::Entity.new(42_u32, UUID.random, type.id.to_u32, Rosegold::Vec3d.new(1, 64, 2),
          0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
      end

      before_each do
        Rosegold::Client.protocol_version = {{protocol}}_u32
        bot_client.player.entity_id = 300_u64
        bot_client.dimension_for_test.entities[42_u64] = vehicle
      end

      after_each { Rosegold::Client.reset_protocol_version! }

      it "does not mistake nearby entities or another passenger for the player's mount" do
        Rosegold::Clientbound::SetPassengers.new(42_u32, [301_u32]).callback(bot_client)

        expect(bot.riding).to be_nil
        expect(bot.riding?).to be_false
        expect(bot.riding?("minecart")).to be_false
      end

      it "checks an optional exact type and exposes the direct mount's type and location" do
        Rosegold::Clientbound::SetPassengers.new(42_u32, [301_u32, 300_u32]).callback(bot_client)

        expect(bot.riding?).to be_true
        expect(bot.riding?("minecart")).to be_true
        expect(bot.riding?("minecraft:minecart")).to be_true
        expect(bot.riding?("horse")).to be_false
        expect(bot.riding?("custom:minecart")).to be_false
        expect(bot.riding.try(&.type)).to eq("minecart")
        expect(bot.riding.try(&.location)).to eq(vehicle.position)
      end

      it "supports living mounts as well as minecarts" do
        type = Rosegold::Entity.metadata_for_protocol.find! { |metadata| metadata.name == "horse" }
        vehicle.entity_type = type.id.to_u32
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)

        expect(bot.riding?).to be_true
        expect(bot.riding?("horse")).to be_true
        expect(bot.riding?("minecart")).to be_false
        expect(bot.riding.try(&.type)).to eq("horse")
      end

      it "does not treat a type name as an entity family" do
        type = Rosegold::Entity.metadata_for_protocol.find! { |metadata| metadata.name == "chest_minecart" }
        vehicle.entity_type = type.id.to_u32
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)

        expect(bot.riding?("chest_minecart")).to be_true
        expect(bot.riding?("minecart")).to be_false
      end

      it "returns the direct mount rather than its parent vehicle" do
        type = Rosegold::Entity.metadata_for_protocol.find! { |metadata| metadata.name == "horse" }
        direct_mount = Rosegold::Entity.new(43_u32, UUID.random, type.id.to_u32,
          Rosegold::Vec3d.new(1, 65, 2), 0_f32, 0_f32, 0_f32, Rosegold::Vec3d::ORIGIN)
        bot_client.dimension_for_test.entities[43_u64] = direct_mount
        Rosegold::Clientbound::SetPassengers.new(42_u32, [43_u32]).callback(bot_client)
        Rosegold::Clientbound::SetPassengers.new(43_u32, [300_u32]).callback(bot_client)

        expect(bot.riding?("horse")).to be_true
        expect(bot.riding?("minecart")).to be_false
        expect(bot.riding.try(&.location)).to eq(direct_mount.position)
      end

      it "keeps riding state when the entity type is unknown" do
        vehicle.entity_type = UInt32::MAX
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)

        expect(bot.riding?).to be_true
        expect(bot.riding?("minecart")).to be_false
        expect(bot.riding.try(&.type)).to be_nil
        expect(bot.riding.try(&.location)).to eq(vehicle.position)
      end

      it "refreshes location without letting a retained snapshot track a former mount" do
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
        snapshot = bot.riding
        initial_location = vehicle.position
        Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

        expect(bot.riding.try(&.location)).to eq(initial_location + Rosegold::Vec3d.new(1, 0, 0))
        expect(snapshot.try(&.location)).to eq(initial_location)

        Rosegold::Clientbound::SetPassengers.new(42_u32, [] of UInt32).callback(bot_client)
        Rosegold::Clientbound::EntityPosition.new(42_u64, 4096_i16, 0_i16, 0_i16, true).callback(bot_client)

        expect(bot.riding).to be_nil
        expect(bot.riding?).to be_false
        expect(bot.riding?("minecart")).to be_false
        expect(snapshot.try(&.location)).to eq(initial_location)
      end

      it "forgets a destroyed mount" do
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
        Rosegold::Clientbound::DestroyEntities.new([42_u64]).callback(bot_client)

        expect(bot.riding).to be_nil
        expect(bot.riding?).to be_false
      end

      it "forgets the mount after respawning or changing dimension" do
        Rosegold::Clientbound::SetPassengers.new(42_u32, [300_u32]).callback(bot_client)
        Rosegold::Clientbound::Respawn.new(0_u32, "minecraft:overworld", 0_i64, 0_u8, -1_i8,
          false, false, false, nil, nil, 0_u32, 63_u32, 0_u8).callback(bot_client)

        expect(bot.riding).to be_nil
        expect(bot.riding?).to be_false
      end
    end
  {% end %}
end
