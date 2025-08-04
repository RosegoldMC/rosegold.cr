require "../spec_helper"

Spectator.describe Rosegold::Bot do
  describe "#radar" do
    it "returns empty array when no players are nearby" do
      # Create a mock client and bot
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Test radar with no entities
      radar_result = bot.radar
      expect(radar_result).to be_empty
    end

    it "filters out non-player entities" do
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Add a non-player entity (zombie = entity_type 121)
      zombie_uuid = UUID.random
      zombie = Rosegold::Entity.new(
        entity_id: 1_u64,
        uuid: zombie_uuid,
        entity_type: 121_u32, # Zombie entity type
        position: Rosegold::Vec3d.new(5, 100, 5),
        pitch: 0_f32,
        yaw: 0_f32,
        head_yaw: 0_f32,
        velocity: Rosegold::Vec3d::ORIGIN,
        living: true
      )
      client.dimension.entities[1_u64] = zombie
      
      # Test radar should not include zombie
      radar_result = bot.radar
      expect(radar_result).to be_empty
    end

    it "detects nearby player entities and calculates distance correctly" do
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Add a player entity (entity_type 111)
      player_uuid = UUID.random
      player = Rosegold::Entity.new(
        entity_id: 2_u64,
        uuid: player_uuid,
        entity_type: 111_u32, # Player entity type
        position: Rosegold::Vec3d.new(3, 100, 4), # 5 blocks away from bot (3² + 4² = 5²)
        pitch: 0_f32,
        yaw: 0_f32,
        head_yaw: 0_f32,
        velocity: Rosegold::Vec3d::ORIGIN,
        living: true
      )
      client.dimension.entities[2_u64] = player
      
      # Test radar detects player
      radar_result = bot.radar
      expect(radar_result.size).to eq(1)
      
      player_info = radar_result.first
      expect(player_info[:uuid]).to eq(player_uuid)
      expect(player_info[:distance]).to be_close(5.0, 0.01)
      expect(player_info[:position]).to eq(Rosegold::Vec3d.new(3, 100, 4))
    end

    it "excludes the bot itself from radar results" do
      client = Rosegold::Client.new("test", 25565)
      bot_uuid = UUID.random
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = bot_uuid
      bot = Rosegold::Bot.new(client)
      
      # Add the bot itself as an entity (this shouldn't happen normally, but test edge case)
      bot_entity = Rosegold::Entity.new(
        entity_id: 3_u64,
        uuid: bot_uuid,
        entity_type: 111_u32,
        position: Rosegold::Vec3d.new(0, 100, 0),
        pitch: 0_f32,
        yaw: 0_f32,
        head_yaw: 0_f32,
        velocity: Rosegold::Vec3d::ORIGIN,
        living: true
      )
      client.dimension.entities[3_u64] = bot_entity
      
      # Test radar should exclude the bot itself
      radar_result = bot.radar
      expect(radar_result).to be_empty
    end

    it "respects max_distance parameter" do
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Add a far player
      far_player = Rosegold::Entity.new(
        entity_id: 4_u64,
        uuid: UUID.random,
        entity_type: 111_u32,
        position: Rosegold::Vec3d.new(20, 100, 0), # 20 blocks away
        pitch: 0_f32,
        yaw: 0_f32,
        head_yaw: 0_f32,
        velocity: Rosegold::Vec3d::ORIGIN,
        living: true
      )
      client.dimension.entities[4_u64] = far_player
      
      # Test radar with max distance of 10 blocks
      radar_result = bot.radar(10.0)
      expect(radar_result).to be_empty
      
      # Test radar with max distance of 25 blocks
      radar_result = bot.radar(25.0)
      expect(radar_result.size).to eq(1)
    end

    it "calculates bearing correctly" do
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Add a player to the east (positive X direction)
      east_player = Rosegold::Entity.new(
        entity_id: 5_u64,
        uuid: UUID.random,
        entity_type: 111_u32,
        position: Rosegold::Vec3d.new(10, 100, 0), # East
        pitch: 0_f32,
        yaw: 0_f32,
        head_yaw: 0_f32,
        velocity: Rosegold::Vec3d::ORIGIN,
        living: true
      )
      client.dimension.entities[5_u64] = east_player
      
      radar_result = bot.radar
      expect(radar_result.size).to eq(1)
      
      # East should be 90 degrees
      player_info = radar_result.first
      expect(player_info[:bearing]).to be_close(90.0, 1.0)
    end
  end
end