require "../spec_helper"

# Integration test for radar functionality
# Tests how radar works with actual packet handling
Spectator.describe "Player Radar Integration" do
  describe "with SpawnLivingEntity packet" do
    it "should detect players spawned via packets" do
      client = Rosegold::Client.new("test", 25565)
      client.player.feet = Rosegold::Vec3d.new(0, 100, 0)
      client.player.uuid = UUID.random
      bot = Rosegold::Bot.new(client)
      
      # Simulate receiving a SpawnLivingEntity packet for a player
      player_uuid = UUID.random
      spawn_packet = Rosegold::Clientbound::SpawnLivingEntity.new(
        entity_id: 1_u64,
        uuid: player_uuid,
        entity_type: 111_u32, # Player entity type
        x: 10.0,
        y: 100.0,
        z: 5.0,
        pitch: 0_f32,
        yaw: 90_f32,
        head_yaw: 90_f32,
        data: 0_u32,
        velocity_x: 0_i16,
        velocity_y: 0_i16,
        velocity_z: 0_i16
      )
      
      # Process the packet (this adds the entity to dimension.entities)
      spawn_packet.callback(client)
      
      # Now radar should detect this player
      radar_result = bot.radar
      expect(radar_result.size).to eq(1)
      
      player_info = radar_result.first
      expect(player_info[:uuid]).to eq(player_uuid)
      expect(player_info[:position]).to eq(Rosegold::Vec3d.new(10.0, 100.0, 5.0))
      
      # Distance should be √(10² + 5²) = √125 ≈ 11.18
      expected_distance = Math.sqrt(10.0*10.0 + 5.0*5.0)
      expect(player_info[:distance]).to be_close(expected_distance, 0.01)
    end
  end
end