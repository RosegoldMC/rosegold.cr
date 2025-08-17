require "../spec_helper"

Spectator.describe "Rosegold::Bot inventory" do
  describe "#count" do
    context "when the item is not in the inventory" do
      it "returns 0" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot

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
            bot.wait_for Rosegold::Clientbound::SetSlot

            bot.chat "/give #{bot.username} minecraft:bucket 16"
            bot.chat "/give #{bot.username} minecraft:bucket 1"
            bot.chat "/give #{bot.username} minecraft:bucket 5"
            bot.wait_ticks 5

            expect(bot.inventory.count("bucket")).to eq 16 + 1 + 5
          end
        end
      end
    end

    context "when there are a lot of items in the inventory" do
      it "doesn't overflow" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot

            bot.chat "/give #{bot.username} minecraft:bucket 513"
            bot.wait_ticks 5

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
            bot.wait_for Rosegold::Clientbound::SetSlot

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
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:stone 42"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:grass_block 43"
            bot.wait_for Rosegold::Clientbound::SetSlot

            expect(bot.inventory.pick("stone")).to eq true
            expect(bot.inventory.main_hand.name).to eq "stone"
            expect(bot.inventory.pick("grass_block")).to eq true
            expect(bot.inventory.main_hand.name).to eq "grass_block"
          end
        end
      end
    end

    context "when the item is in the inventory but not the hotbar" do
      it "returns true" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:stone #{64*9}"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:grass_block 1"
            bot.wait_for Rosegold::Clientbound::SetSlot

            expect(bot.inventory.pick("grass_block")).to eq true
            expect(bot.inventory.main_hand.name).to eq "grass_block"
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
            bot.wait_for Rosegold::Clientbound::SetSlot
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
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:diamond_pickaxe[damage=1550,enchantments={\"minecraft:efficiency\":1}] 1"
            bot.wait_for Rosegold::Clientbound::SetSlot
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
          bot.wait_tick
          bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b},{Slot:6b, id: \"minecraft:diamond_sword\",Count:1b,components:{\"minecraft:damage\":100}}]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.wait_tick

          bot.pitch = 90
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent

          expect(bot.inventory.withdraw_at_least(2, "diamond_sword")).to eq 2

          local_inventory = bot.inventory.inventory.map &.dup
          local_hotbar = bot.inventory.hotbar.map &.dup
          local_content = bot.inventory.content.map &.dup

          expect((local_inventory + local_hotbar).map(&.name).count("diamond_sword")).to eq 2
          expect(local_content.map(&.name)).not_to contain "diamond_sword"

          # Close the chest first so we can reopen it
          bot.inventory.close
          bot.wait_tick

          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent
          bot.wait_tick

          expect(local_inventory.map(&.name)).to match_array bot.inventory.inventory.map(&.name)
          expect(local_hotbar.map(&.name)).to match_array bot.inventory.hotbar.map(&.name)
          expect(local_content.map(&.name)).to match_array bot.inventory.content.map(&.name)
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
          bot.wait_tick
          bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.chat "/give #{bot.username} minecraft:diamond_sword 1"
          bot.wait_for Rosegold::Clientbound::SetSlot

          bot.pitch = 90
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent

          expect(bot.inventory.deposit_at_least(1, "diamond_sword")).to eq 1

          local_inventory = bot.inventory.inventory.map &.dup
          local_hotbar = bot.inventory.hotbar.map &.dup
          local_content = bot.inventory.content.map &.dup

          expect((local_inventory + local_hotbar).map(&.name)).not_to contain "diamond_sword"
          expect(local_content.map(&.name)).to contain "diamond_sword"

          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent

          expect(local_inventory.map(&.name)).to match_array bot.inventory.inventory.map(&.name)
          expect(local_hotbar.map(&.name)).to match_array bot.inventory.hotbar.map(&.name)
          expect(local_content.map(&.name)).to match_array bot.inventory.content.map(&.name)
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
        bot.wait_tick
        bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b}]}"
        bot.chat "/clear"

        bot.pitch = 90
        bot.use_hand
        bot.wait_for Rosegold::Clientbound::SetContainerContent
        bot.inventory.withdraw_at_least(1, "diamond_sword")

        bot.inventory.close

        bot.wait_tick

        slots_before_reload = bot.inventory.slots

        expect((bot.inventory.inventory + bot.inventory.hotbar).map(&.name)).to contain "diamond_sword"
      end
    end

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        slots_after_reload = bot.inventory.slots

        expect(slots_before_reload.try &.size).to eq slots_after_reload.try &.size
        expect(slots_before_reload.try &.map(&.name)).to eq slots_after_reload.try &.map(&.name)
        expect(slots_before_reload.try &.map(&.slot_number)).to eq slots_after_reload.try &.map(&.slot_number)
      end
    end
  end

  describe "#throw_all_of" do
    it "throws all of the specified item" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.chat "/give #{bot.username} minecraft:diamond_sword 4"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.chat "/give #{bot.username} minecraft:stone 200"
          bot.wait_for Rosegold::Clientbound::SetSlot

          bot.look = Rosegold::Look.new 0, 0
          expect(bot.inventory.throw_all_of "diamond_sword").to eq 4
          expect(bot.inventory.throw_all_of "stone").to eq 200

          bot.wait_tick

          expect(bot.inventory.inventory.map(&.name)).not_to contain "diamond_sword"
          expect(bot.inventory.hotbar.map(&.name)).not_to contain "diamond_sword"
          expect(bot.inventory.inventory.map(&.name)).not_to contain "stone"
          expect(bot.inventory.hotbar.map(&.name)).not_to contain "stone"
        end
      end
    end
  end

  describe "#replenish" do
    context "when player already has enough items" do
      it "returns current count without withdrawing" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:stone 15"
            bot.wait_for Rosegold::Clientbound::SetSlot

            result = bot.inventory.replenish 10, "stone"
            expect(result).to eq 15
            expect(bot.inventory.count("stone")).to eq 15
          end
        end
      end
    end

    context "when player has some items but needs more" do
      it "withdraws additional items from container" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
            bot.wait_tick
            bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b, id: \"minecraft:stone\",Count:10b}]}"
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:stone 2"
            bot.wait_for Rosegold::Clientbound::SetSlot

            bot.pitch = 90
            bot.use_hand
            bot.wait_for Rosegold::Clientbound::SetContainerContent

            initial_count = bot.inventory.count("stone", bot.inventory.inventory + bot.inventory.hotbar)
            result = bot.inventory.replenish 5, "stone"

            expect(result).to be > initial_count
          end
        end
      end
    end

    context "when player has no items" do
      it "withdraws items from container" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
            bot.wait_tick
            bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b, id: \"minecraft:diamond\",Count:5b}]}"
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot

            bot.pitch = 90
            bot.use_hand
            bot.wait_for Rosegold::Clientbound::SetContainerContent

            result = bot.inventory.replenish 3, "diamond"
            expect(result).to be > 0
            expect(bot.inventory.count("diamond", bot.inventory.inventory + bot.inventory.hotbar)).to be > 0
          end
        end
      end
    end

    context "when container doesn't have enough items" do
      it "withdraws as many as available" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
            bot.wait_tick
            bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b, id: \"minecraft:gold_ingot\",Count:2b}]}"
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.chat "/give #{bot.username} minecraft:gold_ingot 1"
            bot.wait_for Rosegold::Clientbound::SetSlot

            bot.pitch = 90
            bot.use_hand
            bot.wait_for Rosegold::Clientbound::SetContainerContent

            initial_count = bot.inventory.count("gold_ingot", bot.inventory.inventory + bot.inventory.hotbar)
            result = bot.inventory.replenish 5, "gold_ingot"

            expect(result).to be > initial_count
            expect(result).to be < 5
          end
        end
      end
    end
  end
end
