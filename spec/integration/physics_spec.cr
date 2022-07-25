require "../spec_helper"

Spectator.describe Rosegold::Physics do
  it "should fall due to gravity" do
    Rosegold::Client.new("localhost", 25565).start do |client|
      sleep 2
      client.queue_packet Rosegold::Serverbound::Chat.new "/tp 1 -58 1"
      sleep 1
      expect(client.player.feet).to eq(Rosegold::Vec3d.new(1.5, -60, 1.5))
    end
  end

  it "can move to location successfully" do
    Rosegold::Client.new("localhost", 25565).start do |client|
      sleep 2
      client.queue_packet Rosegold::Serverbound::Chat.new "/tp 1 -60 1"
      sleep 1
      client.physics.try do |physics|
        physics.movement_speed = 0.235
        physics.movement_target = Rosegold::Vec3d.new(5.5, -60, 5.5)
        sleep 2
        expect(client.player.feet).to eq(Rosegold::Vec3d.new(5.5, -60, 5.5))
        physics.movement_target = Rosegold::Vec3d.new(5.5, -60, -5.5)
        sleep 3
        expect(client.player.feet).to eq(Rosegold::Vec3d.new(5.5, -60, -5.5))
      end
    end
  end
end
