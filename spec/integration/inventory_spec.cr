require "../spec_helper"

Spectator.describe Rosegold::Bot do
  describe "#count" do
    context "when the item is not in the inventory" do
      it "returns 0" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            sleep 1

            expect(bot.inventory.count("bucket")).to eq 0
          end
        end
      end
    end

    context "when there are several stacks of items in the inventory" do
      it "returns the sum of their counts" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            sleep 1

            bot.chat "/give #{bot.username} minecraft:bucket 16"
            bot.chat "/give #{bot.username} minecraft:bucket 1"
            bot.chat "/give #{bot.username} minecraft:bucket 5"
            sleep 1

            expect(bot.inventory.count("bucket")).to eq 16+1+5
          end
        end
      end
    end

    context "when there are a lot of items in the inventory" do
      it "doesn't overflow" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            sleep 1

            bot.chat "/give #{bot.username} minecraft:bucket 513"
            sleep 1

            expect(bot.inventory.count("bucket")).to eq 513
          end
        end
      end
    end
  end

  describe "#pick" do
    context "when the item is not in the inventory" do
      it "returns false" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"

            sleep 1

            expect(bot.inventory.pick("diamond_pickaxe")).to eq false
            expect(bot.inventory.pick("stone")).to eq false
            expect(bot.inventory.pick("diamond_pickaxe")).to eq false
          end
        end
      end
    end

    context "when the item is in the hotbar" do
      it "returns true" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.chat "/give #{bot.username} minecraft:stone 42"
            bot.chat "/give #{bot.username} minecraft:grass_block 43"
            sleep 1

            expect(bot.inventory.pick("stone")).to eq true
            expect(bot.inventory.main_hand.item_id).to eq "stone"
            expect(bot.inventory.pick("grass_block")).to eq true
            expect(bot.inventory.main_hand.item_id).to eq "grass_block"
          end
        end
      end
    end

    context "when the item is in the inventory but not the hotbar" do
      it "returns true" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.chat "/give #{bot.username} minecraft:stone #{64*9}"
            bot.chat "/give #{bot.username} minecraft:grass_block 1"
            sleep 1

            expect(bot.inventory.pick("grass_block")).to eq true
            expect(bot.inventory.main_hand.item_id).to eq "grass_block"
          end
        end
      end
    end
  end

  describe "#pick!" do
    context "when the item is not in the inventory" do
      it "raises exception" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            sleep 1
            expect { bot.inventory.pick!("diamond_pickaxe") }.to raise_error(Rosegold::Inventory::ItemNotFoundError)
          end
        end
      end
    end

    context "when the only pickable ite is in need of repair (diamond/netherite and enchanted, with <=12 dura left)" do
      it "raises exception" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.chat "/give #{bot.username} minecraft:diamond_pickaxe{Damage:1550,Enchantments:[{id:efficiency,lvl:1}]} 1"
            expect { bot.inventory.pick!("diamond_pickaxe") }.to raise_error(Rosegold::Inventory::ItemNotFoundError)
          end
        end
      end
    end
  end

  describe "#withdraw_at_least" do
    it "updates the inventory locally to be the same as externally" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
          sleep 1
          bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b}]}"
          bot.chat "/clear"
          sleep 1

          bot.pitch = 90
          bot.use_hand
          sleep 1
          expect(bot.inventory.withdraw_at_least(1, "diamond_sword")).to eq 1

          sleep 1

          local_inventory = bot.inventory.inventory.map &.dup
          local_hotbar = bot.inventory.hotbar.map &.dup
          local_content = bot.inventory.content.map &.dup

          expect((local_inventory + local_hotbar).map(&.item_id)).to contain "diamond_sword"
          expect(local_content.map(&.item_id)).not_to contain "diamond_sword"

          sleep 1
          bot.use_hand
          sleep 1

          expect(local_inventory.map(&.item_id)).to match_array bot.inventory.inventory.map(&.item_id)
          expect(local_hotbar.map(&.item_id)).to match_array bot.inventory.hotbar.map(&.item_id)
          expect(local_content.map(&.item_id)).to match_array bot.inventory.content.map(&.item_id)
          expect(local_inventory.map(&.slot_number)).to match_array bot.inventory.inventory.map(&.slot_number)
          expect(local_hotbar.map(&.slot_number)).to match_array bot.inventory.hotbar.map(&.slot_number)
          expect(local_content.map(&.slot_number)).to match_array bot.inventory.content.map(&.slot_number)
        end
      end
    end
  end

  describe "#deposit_at_least" do
    it "updates the inventory locally to be the same as externally" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
          sleep 1
          bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[]}"
          bot.chat "/clear"
          sleep 1
          bot.chat "/give #{bot.username} minecraft:diamond_sword 1"
          sleep 1

          bot.pitch = 90
          bot.use_hand
          sleep 1

          expect(bot.inventory.deposit_at_least(1, "diamond_sword")).to eq 1

          local_inventory = bot.inventory.inventory.map &.dup
          local_hotbar = bot.inventory.hotbar.map &.dup
          local_content = bot.inventory.content.map &.dup

          expect((local_inventory + local_hotbar).map(&.item_id)).not_to contain "diamond_sword"
          expect(local_content.map(&.item_id)).to contain "diamond_sword"

          sleep 1
          bot.use_hand
          sleep 1

          expect(local_inventory.map(&.item_id)).to match_array bot.inventory.inventory.map(&.item_id)
          expect(local_hotbar.map(&.item_id)).to match_array bot.inventory.hotbar.map(&.item_id)
          expect(local_content.map(&.item_id)).to match_array bot.inventory.content.map(&.item_id)
          expect(local_inventory.map(&.slot_number)).to match_array bot.inventory.inventory.map(&.slot_number)
          expect(local_hotbar.map(&.slot_number)).to match_array bot.inventory.hotbar.map(&.slot_number)
          expect(local_content.map(&.slot_number)).to match_array bot.inventory.content.map(&.slot_number)
        end
      end
    end
  end

  it "updates the player inventory upon container window closure" do
    slots_before_reload = nil
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp #{bot.username} -10 -60 -10"
        bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
        sleep 1
        bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b}]}"
        bot.chat "/clear"
        sleep 1

        bot.pitch = 90
        bot.use_hand
        sleep 1
        bot.inventory.withdraw_at_least(1, "diamond_sword")

        sleep 1

        bot.inventory.close

        sleep 1

        slots_before_reload = bot.inventory.slots

        expect((bot.inventory.inventory + bot.inventory.hotbar).map(&.item_id)).to contain "diamond_sword"
      end
    end

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        slots_after_reload = bot.inventory.slots

        expect(slots_before_reload.try &.size).to eq slots_after_reload.try &.size
        expect(slots_before_reload.try &.map(&.item_id)).to eq slots_after_reload.try &.map(&.item_id)
        expect(slots_before_reload.try &.map(&.slot_number)).to eq slots_after_reload.try &.map(&.slot_number)
      end
    end
  end
end
