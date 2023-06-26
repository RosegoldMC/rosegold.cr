require "../spec_helper"

Spectator.describe Rosegold::Bot do
  # describe "#pick" do
  #   context "when the item is not in the inventory" do
  #     it "returns false" do
  #       client.join_game do |client|
  #         Rosegold::Bot.new(client).try do |bot|
  #           bot.chat "/clear"

  #           sleep 1

  #           expect(bot.inventory.pick("diamond_pickaxe")).to eq false
  #           expect(bot.inventory.pick("stone")).to eq false
  #           expect(bot.inventory.pick("diamond_pickaxe")).to eq false
  #         end
  #       end
  #     end
  #   end

  #   context "when the item is in the hotbar" do
  #     it "returns true" do
  #       client.join_game do |client|
  #         Rosegold::Bot.new(client).try do |bot|
  #           bot.chat "/clear"
  #           bot.chat "/give #{bot.username} minecraft:stone 42"
  #           bot.chat "/give #{bot.username} minecraft:grass_block 43"
  #           sleep 1

  #           expect(bot.inventory.pick("stone")).to eq true
  #           expect(bot.inventory.main_hand.item_id).to eq "stone"
  #           expect(bot.inventory.pick("grass_block")).to eq true
  #           expect(bot.inventory.main_hand.item_id).to eq "grass_block"
  #         end
  #       end
  #     end
  #   end

  #   context "when the item is in the inventory but not the hotbar" do
  #     it "returns true" do
  #       client.join_game do |client|
  #         Rosegold::Bot.new(client).try do |bot|
  #           bot.chat "/clear"
  #           bot.chat "/give #{bot.username} minecraft:stone #{64*9}"
  #           bot.chat "/give #{bot.username} minecraft:grass_block 1"
  #           sleep 1

  #           expect(bot.inventory.pick("grass_block")).to eq true
  #           expect(bot.inventory.main_hand.item_id).to eq "grass_block"
  #         end
  #       end
  #     end
  #   end
  # end

  # describe "#pick!" do
  #   context "when the item is not in the inventory" do
  #     it "raises exception" do
  #       client.join_game do |client|
  #         Rosegold::Bot.new(client).try do |bot|
  #           bot.chat "/clear"
  #           sleep 1
  #           expect { bot.inventory.pick!("diamond_pickaxe") }.to raise_error(Rosegold::Inventory::ItemNotFoundError)
  #         end
  #       end
  #     end
  #   end

  #   context "when the only pickable ite is in need of repair (diamond/netherite and enchanted, with <=12 dura left)" do
  #     it "raises exception" do
  #       client.join_game do |client|
  #         Rosegold::Bot.new(client).try do |bot|
  #           bot.chat "/clear"
  #           bot.chat "/give #{bot.username} minecraft:diamond_pickaxe{Damage:1550,Enchantments:[{id:efficiency,lvl:1}]} 1"
  #           expect { bot.inventory.pick!("diamond_pickaxe") }.to raise_error(Rosegold::Inventory::ItemNotFoundError)
  #         end
  #       end
  #     end
  #   end
  # end

  # describe "#withdraw_at_least" do
  #   it "withdraws the item without failing" do
  #     client.join_game do |client|
  #       Rosegold::Bot.new(client).try do |bot|
  #         bot.chat "/fill ~ ~ ~ ~ ~ ~ minecraft:air"
  #         sleep 1
  #         bot.chat "/setblock ~ ~ ~ minecraft:chest{Items:[{Slot:7b, id: \"minecraft:diamond_sword\",Count:1b}]}"
  #         bot.chat "/clear"
  #         sleep 1

  #         bot.pitch = 90
  #         bot.use_hand
  #         sleep 1
  #         expect(bot.inventory.withdraw_at_least(1, "diamond_sword")).to eq 1
  #         sleep 1
  #         bot.use_hand
  #         sleep 1
          
  #         expect((bot.inventory.inventory + bot.inventory.hotbar).map(&.item_id)).to contain "diamond_sword"
  #         expect(bot.inventory.content.map(&.item_id)).not_to contain "diamond_sword"
  #       end
  #     end
  #   end
  # end

  describe "#deposit_at_least" do
    it "deposits the item without failing" do
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

          sleep 1
          bot.use_hand
          sleep 1

          expect((bot.inventory.inventory + bot.inventory.hotbar).map(&.item_id)).not_to contain "diamond_sword"
          expect(bot.inventory.content.map(&.item_id)).to contain "diamond_sword"
        end

      end
    end
  end
end
