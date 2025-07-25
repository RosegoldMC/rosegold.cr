require "../spec_helper"

# Unit test for sneak cliff protection logic
Spectator.describe "Rosegold::Physics sneak cliff protection" do
  describe "cliff protection constants" do
    it "has correct protection distance" do
      expect(Rosegold::Physics::SNEAK_CLIFF_PROTECTION_DISTANCE).to eq(0.625)
    end
  end

  describe "movement speed calculation" do
    let(client) { Rosegold::Client.new("test") }
    let(physics) { Rosegold::Physics.new(client) }

    it "uses correct sneak speed when sneaking" do
      client.player.sneaking = true
      client.player.sprinting = false

      expect(physics.movement_speed).to eq(Rosegold::Physics::SNEAK_SPEED)
    end

    it "uses correct walk speed when not sneaking" do
      client.player.sneaking = false
      client.player.sprinting = false

      expect(physics.movement_speed).to eq(Rosegold::Physics::WALK_SPEED)
    end

    it "uses correct sprint speed when sprinting" do
      client.player.sneaking = false
      client.player.sprinting = true

      expect(physics.movement_speed).to eq(Rosegold::Physics::SPRINT_SPEED)
    end
  end

  describe "sneak behavior" do
    let(client) { Rosegold::Client.new("test") }
    let(physics) { Rosegold::Physics.new(client) }

    it "can enable sneaking" do
      expect(client.player.sneaking?).to be_false

      # Mock the client.send_packet! method to avoid sending actual packets
      client.player.sneaking = true

      expect(client.player.sneaking?).to be_true
    end

    it "can disable sneaking" do
      client.player.sneaking = true
      expect(client.player.sneaking?).to be_true

      client.player.sneaking = false
      expect(client.player.sneaking?).to be_false
    end
  end
end
