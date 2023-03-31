require "../spec_helper"

Spectator.describe Rosegold::Physics do
  it "should fall due to gravity" do
    Rosegold::Client.new("localhost", 25565).join_game do |client|
      sleep 2 # load chunks
      client.queue_packet Rosegold::Serverbound::Chat.new "/tp 1 -58 1"
      sleep 1 # teleport
      sleep 1 # fall
      expect(client.player.feet).to eq(Rosegold::Vec3d.new(1.5, -60, 1.5))
    end
  end

  it "can move to location successfully" do
    Rosegold::Client.new("localhost", 25565).join_game do |client|
      sleep 2 # load chunks
      client.queue_packet Rosegold::Serverbound::Chat.new "/tp 1 -60 1"
      sleep 1 # teleport

      client.physics.move Rosegold::Vec3d.new(5.5, -60, 5.5)
      expect(client.player.feet).to eq(Rosegold::Vec3d.new(5.5, -60, 5.5))

      client.physics.move Rosegold::Vec3d.new(5.5, -60, -5.5)
      expect(client.player.feet).to eq(Rosegold::Vec3d.new(5.5, -60, -5.5))
    end
  end
end
