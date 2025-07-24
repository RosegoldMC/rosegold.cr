require "../spec_helper"

# Unit test for sneak cliff protection logic
Spectator.describe "Rosegold::Physics sneak cliff protection" do
  let(dimension) { Rosegold::Dimension.new }
  let(client) { Rosegold::Client.new("test") }
  let(physics) { Rosegold::Physics.new(client) }

  describe "#would_fall_off_cliff?" do
    it "returns false when not sneaking" do
      client.player.sneaking = false
      client.player.feet = Rosegold::Vec3d.new(0, 0, 0)
      
      # Should not check cliff protection when not sneaking
      result = physics.send(:would_fall_off_cliff?, Rosegold::Vec3d.new(1, 0, 0))
      expect(result).to be_false
    end

    it "returns false when sneaking but ground is close" do
      client.player.sneaking = true
      client.player.feet = Rosegold::Vec3d.new(0, 1, 0)
      
      # Mock dimension to have solid ground just below
      allow(physics.send(:dimension)).to receive(:block_state).and_return(1_u16) # stone block state
      
      result = physics.send(:would_fall_off_cliff?, Rosegold::Vec3d.new(1, 1, 0))
      expect(result).to be_false
    end
  end

  describe "#has_solid_ground_at?" do
    it "returns false for air blocks" do
      # Mock dimension to return air block state (0)
      allow(physics.send(:dimension)).to receive(:block_state).and_return(nil)
      
      result = physics.send(:has_solid_ground_at?, Rosegold::Vec3d.new(0, 0, 0))
      expect(result).to be_false
    end

    it "returns true for solid blocks" do
      # Mock dimension to return stone block state and collision shapes
      allow(physics.send(:dimension)).to receive(:block_state).and_return(1_u16)
      
      result = physics.send(:has_solid_ground_at?, Rosegold::Vec3d.new(0, 1, 0))
      expect(result).to be_true
    end
  end
end