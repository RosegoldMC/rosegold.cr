require "../spec_helper"

Spectator.describe "Rosegold::Bot container API" do
  describe "#container_type" do
    it "returns nil when no container is open" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.wait_ticks 5
          expect(bot.container_type).to be_nil
        end
      end
    end

    it "returns ChestMenu when a chest is open" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          admin.tp 30, -60, 30
          admin.setblock 30, -61, 30, "chest"
          admin.clear
          bot.wait_ticks 2
          bot.pitch = 90
          bot.wait_ticks 20

          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent
          expect(bot.container_type).to eq Rosegold::ChestMenu
          bot.inventory.close
        end
      end
    end
  end

  describe "#open_container_handle" do
    it "opens a container and yields a handle" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          admin.tp 30, -60, 30
          admin.setblock 30, -61, 30, "chest{Items:[{Slot:0b, id: \"minecraft:diamond\",count:3b}]}"
          admin.clear
          bot.wait_ticks 2
          bot.pitch = 90
          bot.wait_ticks 20

          bot.open_container_handle do |handle|
            expect(handle).to be_a Rosegold::ContainerHandle
            expect(handle.count_in_container("diamond")).to eq 3
          end
        end
      end
    end
  end

  describe "ContainerOpened event" do
    it "emits ContainerOpened when a container is opened" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          admin.tp 30, -60, 30
          admin.setblock 30, -61, 30, "chest"
          bot.wait_ticks 2
          bot.pitch = 90
          bot.wait_ticks 20

          received_event = nil
          client.on(Rosegold::Event::ContainerOpened) do |event|
            received_event = event
          end

          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent
          bot.wait_tick

          expect(received_event).not_to be_nil
          if event = received_event
            expect(event.menu).to be_a Rosegold::ChestMenu
          end
          bot.inventory.close
        end
      end
    end
  end
end
