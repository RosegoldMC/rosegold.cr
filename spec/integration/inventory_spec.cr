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

    context "when picking items with different durabilities" do
      it "picks items with lower durability first" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot
            # Give undamaged diamond pickaxe first (will go to hotbar slot 0)
            bot.chat "/give #{bot.username} minecraft:diamond_pickaxe"
            bot.wait_for Rosegold::Clientbound::SetSlot
            # Give damaged diamond pickaxe (will go to hotbar slot 1)
            bot.chat "/give #{bot.username} minecraft:diamond_pickaxe[damage=1400]"
            bot.wait_for Rosegold::Clientbound::SetSlot

            # Switch away from the pickaxes first
            bot.hotbar_selection = 3_u8

            # Pick should select the damaged one (lower durability)
            expect(bot.inventory.pick("diamond_pickaxe")).to eq true

            # Verify we picked the damaged pickaxe
            picked_pickaxe = bot.inventory.main_hand
            expect(picked_pickaxe.name).to eq "diamond_pickaxe"
            expect(picked_pickaxe.damage).to eq 1400 # Should be the damaged one
            expect(picked_pickaxe.durability).to eq 161
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
          bot.chat "/tp #{bot.username} 30 -60 30"
          bot.chat "/setblock 21 -60 21 minecraft:air"
          bot.wait_tick
          bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b},{Slot:6b, id: \"minecraft:diamond_sword\",Count:1b,components:{\"minecraft:damage\":100}}]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.pitch = 90
          bot.wait_ticks 20

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

    it "withdraws items with lower durability first" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          # Teleport to known location and clear area
          bot.chat "/tp 30 -60 30"
          bot.wait_tick
          bot.chat "/fill 29 -62 29 31 -58 31 minecraft:air"
          bot.wait_tick
          # Create chest with two diamond pickaxes: one undamaged, one heavily damaged
          bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[{Slot:0b, id: \"minecraft:diamond_pickaxe\",Count:1b},{Slot:1b, id: \"minecraft:diamond_pickaxe\",Count:1b,components:{\"minecraft:damage\":1400}}]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.wait_tick

          bot.pitch = 90
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent

          # Withdraw 1 diamond pickaxe - should get the damaged one first (lower durability)
          expect(bot.inventory.withdraw_at_least(1, "diamond_pickaxe")).to eq 1

          # Check that the withdrawn pickaxe is the damaged one
          withdrawn_pickaxe = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "diamond_pickaxe" }
          expect(withdrawn_pickaxe).not_to be_nil
          if pickaxe = withdrawn_pickaxe
            expect(pickaxe.damage).to eq 1400    # Should be the heavily damaged one
            expect(pickaxe.durability).to eq 161 # Diamond pickaxe max durability (1561) - damage (1400)
          end

          # Verify the undamaged pickaxe is still in the chest
          undamaged_pickaxe = bot.inventory.content.find { |slot| slot.name == "diamond_pickaxe" }
          expect(undamaged_pickaxe).not_to be_nil
          if pickaxe = undamaged_pickaxe
            expect(pickaxe.damage).to eq 0 # Should be undamaged
          end
        end
      end
    end

    it "withdraws multiple items in durability order" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          # Teleport to known location and clear area
          bot.chat "/tp 30 -60 30"
          bot.wait_tick
          bot.chat "/fill 29 -62 29 31 -58 31 minecraft:air"
          bot.wait_tick
          # Create chest with multiple diamond swords of varying durability
          bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[{Slot:0b, id: \"minecraft:diamond_sword\",Count:1b},{Slot:1b, id: \"minecraft:diamond_sword\",Count:1b,components:{\"minecraft:damage\":800}},{Slot:2b, id: \"minecraft:diamond_sword\",Count:1b,components:{\"minecraft:damage\":1200}},{Slot:3b, id: \"minecraft:diamond_sword\",Count:1b,components:{\"minecraft:damage\":400}}]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.wait_tick

          bot.pitch = 90
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent

          # Withdraw 3 swords - should get the most damaged ones first
          expect(bot.inventory.withdraw_at_least(3, "diamond_sword")).to eq 3

          # Check that we got the 3 most damaged swords
          withdrawn_swords = (bot.inventory.inventory + bot.inventory.hotbar).select { |slot| slot.name == "diamond_sword" }
          expect(withdrawn_swords.size).to eq 3

          # Sort by damage to verify we got the most damaged ones
          damages = withdrawn_swords.map(&.damage).sort!
          expect(damages).to eq [400, 800, 1200] # Should be the 3 most damaged ones

          # Verify the undamaged sword is still in the chest
          remaining_sword = bot.inventory.content.find { |slot| slot.name == "diamond_sword" }
          expect(remaining_sword).not_to be_nil
          if sword = remaining_sword
            expect(sword.damage).to eq 0 # Should be undamaged
          end
        end
      end
    end
  end

  describe "#deposit_at_least" do
    it "updates the inventory locally to be the same as externally" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          # Teleport to known location and clear area
          bot.chat "/tp 30 -60 30"
          bot.wait_tick
          bot.chat "/fill 29 -62 29 31 -58 31 minecraft:air"
          bot.wait_tick
          bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[]}"
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.chat "/give #{bot.username} minecraft:diamond_sword 1"
          bot.wait_for Rosegold::Clientbound::SetSlot

          bot.pitch = 90
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent
          bot.wait_tick

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
        bot.chat "/tp 30 -60 30"
        bot.wait_tick
        bot.wait_tick
        bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b}]}"
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
        expect(slots_before_reload.try &.map(&.name).sort!).to eq slots_after_reload.try &.map(&.name).sort!
        expect(slots_before_reload.try &.count(&.name.==("diamond_sword"))).to eq slots_after_reload.try &.count(&.name.==("diamond_sword"))
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

    it "throws all lava buckets (single-stack items)" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot
          bot.chat "/give #{bot.username} minecraft:lava_bucket 33"
          bot.wait_for Rosegold::Clientbound::SetSlot

          bot.look = Rosegold::Look.new 0, 0
          expect(bot.inventory.throw_all_of "lava_bucket").to eq 33

          bot.wait_tick

          expect(bot.inventory.inventory.map(&.name)).not_to contain "lava_bucket"
          expect(bot.inventory.hotbar.map(&.name)).not_to contain "lava_bucket"
        end
      end

      # Relog and verify inventory is still clear
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          expect(bot.inventory.inventory.map(&.name)).not_to contain "lava_bucket"
          expect(bot.inventory.hotbar.map(&.name)).not_to contain "lava_bucket"
        end
      end
    end

    it "throws all items from an open container" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "throws all items from an open container"
          # Teleport to known location and clear area
          bot.chat "/tp 30 -60 30"
          bot.wait_tick

          # Create chest with cobblestone inside
          bot.chat "/setblock 30 -61 30 minecraft:chest{Items:[{Slot:0b, id: \"minecraft:cobblestone\",Count:32b},{Slot:1b, id: \"minecraft:cobblestone\",Count:20b}]}"
          bot.wait_tick

          bot.chat "/clear"
          bot.wait_for Rosegold::Clientbound::SetSlot

          # Open the chest
          bot.pitch = 90
          bot.wait_ticks 10
          bot.use_hand
          bot.wait_for Rosegold::Clientbound::SetContainerContent
          bot.wait_tick
          bot.pitch = 0

          # Verify we have cobblestone in container
          expect(bot.inventory.content.map(&.name)).to contain "cobblestone"
          expect(bot.inventory.count("cobblestone", bot.inventory.content)).to eq 2

          # Throw all cobblestone from the open container
          expect(bot.inventory.throw_all_of "cobblestone").to eq 2

          bot.wait_tick

          # Verify all cobblestone is gone from container
          expect(bot.inventory.content.map(&.name)).not_to contain "cobblestone"
          expect(bot.inventory.count("cobblestone", bot.inventory.content)).to eq 0

          # Close container
          bot.inventory.close
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
            bot.chat "/setblock ~ ~ ~ air"
            bot.chat "/setblock ~ ~-1 ~ minecraft:chest{Items:[{Slot:0b, id: \"minecraft:stone\",Count:10b}]}"
            bot.chat "/clear"
            bot.wait_tick
            bot.chat "/give #{bot.username} minecraft:stone 2"
            bot.wait_for Rosegold::Clientbound::SetSlot
            bot.pitch = 90
            bot.wait_ticks 5
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

  describe "#shift_click_equipment" do
    context "when shift-clicking equipment items without a container open" do
      it "shift-click equipment functionality" do
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            bot.chat "/clear"
            bot.wait_for Rosegold::Clientbound::SetSlot

            # Give one full set of diamond armor and shield
            bot.chat "/give #{bot.username} minecraft:diamond_helmet 1"
            bot.chat "/give #{bot.username} minecraft:diamond_chestplate 1"
            bot.chat "/give #{bot.username} minecraft:diamond_leggings 1"
            bot.chat "/give #{bot.username} minecraft:diamond_boots 1"
            bot.chat "/give #{bot.username} minecraft:shield 1"
            bot.wait_ticks 5

            # Find equipment items in inventory
            helmet_slot = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "diamond_helmet" }
            chestplate_slot = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "diamond_chestplate" }
            leggings_slot = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "diamond_leggings" }
            boots_slot = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "diamond_boots" }
            shield_slot = (bot.inventory.inventory + bot.inventory.hotbar).find { |slot| slot.name == "shield" }

            # Shift-click all equipment items to equip them
            helmet_slot.try { |slot| bot.inventory.send_click slot.slot_number, 0, :shift }
            bot.wait_ticks 2
            chestplate_slot.try { |slot| bot.inventory.send_click slot.slot_number, 0, :shift }
            bot.wait_ticks 2
            leggings_slot.try { |slot| bot.inventory.send_click slot.slot_number, 0, :shift }
            bot.wait_ticks 2
            boots_slot.try { |slot| bot.inventory.send_click slot.slot_number, 0, :shift }
            bot.wait_ticks 2
            shield_slot.try { |slot| bot.inventory.send_click slot.slot_number, 0, :shift }
            bot.wait_ticks 2

            # Assert equipment is equipped
            expect(bot.inventory.helmet.name).to eq("diamond_helmet")
            expect(bot.inventory.chestplate.name).to eq("diamond_chestplate")
            expect(bot.inventory.leggings.name).to eq("diamond_leggings")
            expect(bot.inventory.boots.name).to eq("diamond_boots")
            expect(bot.inventory.off_hand.name).to eq("shield")
          end
        end

        # Relog and assert equipment persists
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            expect(bot.inventory.helmet.name).to eq("diamond_helmet")
            expect(bot.inventory.chestplate.name).to eq("diamond_chestplate")
            expect(bot.inventory.leggings.name).to eq("diamond_leggings")
            expect(bot.inventory.boots.name).to eq("diamond_boots")
            expect(bot.inventory.off_hand.name).to eq("shield")
          end
        end
      end
    end
  end
end
