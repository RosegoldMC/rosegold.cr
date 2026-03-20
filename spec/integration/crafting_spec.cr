require "../spec_helper"

private def wait_for_recipes(bot, min_count = 100, timeout_ticks = 60)
  bot.chat "/recipe give @s *"
  timeout_ticks.times do
    break if bot.recipe_registry.size >= min_count
    bot.wait_ticks 1
  end
end

Spectator.describe "Rosegold::Bot crafting" do
  describe "recipe registry" do
    it "receives recipes on login" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)

          expect(bot.recipe_registry.size).to be > 0
        end
      end
    end

    it "contains common recipes like oak_planks and stick" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)

          # Debug: show registry state if oak_planks not found
          oak_recipes = bot.recipes_for("oak_planks")
          if oak_recipes.empty?
            registry = bot.recipe_registry
            sample_ids = registry.entries.values.first(10).map { |e|
              "id=#{e.id} result=#{e.result_item_id} type=#{e.display.class.name.split("::").last}"
            }
            parts = ["oak_planks not found"]
            parts << "registry=#{registry.size}"
            parts << "protocol=#{Rosegold::Client.protocol_version}"
            parts << "history=[#{registry.add_history.join(" | ")}]"
            parts << "sample=[#{sample_ids.join("; ")}]"
            if err = registry.last_parse_error
              parts << "PARSE_ERROR: #{err} (expected #{registry.last_expected_count})"
            end
            fail parts.join(". ")
          end
          expect(bot.recipes_for("stick")).to_not be_empty
        end
      end
    end
  end

  describe "#recipes_for" do
    it "finds recipes for a valid item" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)

          recipes = bot.recipes_for("oak_planks")
          expect(recipes.size).to be >= 1
        end
      end
    end

    it "returns empty for nonexistent items" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)

          recipes = bot.recipes_for("nonexistent_item_12345")
          expect(recipes).to be_empty
        end
      end
    end
  end

  describe "#can_craft?" do
    it "returns true when materials are available" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_log 1"
          bot.wait_ticks 10

          recipes = bot.recipes_for("oak_planks")
          expect(recipes).to_not be_empty
          expect(bot.can_craft?(recipes.first)).to be_true
        end
      end
    end

    it "returns false with empty inventory" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 10

          recipes = bot.recipes_for("oak_planks")
          expect(recipes).to_not be_empty
          expect(bot.can_craft?(recipes.first)).to be_false
        end
      end
    end
  end

  describe "#craft" do
    it "crafts planks from logs in player inventory grid" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_log 4"
          bot.wait_ticks 10

          bot.craft("oak_planks", 4)
          bot.wait_ticks 10

          expect(bot.inventory.count("oak_planks")).to be >= 16
        end
      end
    end

    it "crafts sticks from planks" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_planks 2"
          bot.wait_ticks 10

          bot.craft("stick")
          bot.wait_ticks 10

          expect(bot.inventory.count("stick")).to be >= 4
        end
      end
    end

    it "crafts multiple items with count > 1" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_log 8"
          bot.wait_ticks 10

          bot.craft("oak_planks", 8)
          bot.wait_ticks 10

          expect(bot.inventory.count("oak_planks")).to be >= 32
        end
      end
    end

    it "crafts with a crafting table for 3x3 recipes" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/tp #{bot.username} 0 -59 0"
          bot.wait_ticks 10
          bot.chat "/setblock 2 -59 0 minecraft:crafting_table"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:cobblestone 8"
          bot.wait_ticks 10

          bot.craft("furnace", table: Rosegold::Vec3i.new(2, -59, 0))
          bot.wait_ticks 10

          expect(bot.inventory.count("furnace")).to be >= 1
        end
      end
    end
  end

  describe "#craft_all" do
    it "crafts maximum amount from available materials" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_log 4"
          bot.wait_ticks 10

          bot.craft_all("oak_planks")
          bot.wait_ticks 10

          expect(bot.inventory.count("oak_planks")).to be >= 16
        end
      end
    end
  end

  describe "error cases" do
    it "raises CraftingError when crafting with no materials" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)
          bot.chat "/clear"
          bot.wait_ticks 10

          expect { bot.craft("diamond_sword") }.to raise_error(Rosegold::Bot::CraftingError)
        end
      end
    end

    it "raises CraftingError for nonexistent recipe" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          wait_for_recipes(bot)

          expect { bot.craft("nonexistent_item_12345") }.to raise_error(Rosegold::Bot::CraftingError)
        end
      end
    end
  end

  describe "#craft_pattern" do
    it "crafts planks from a log using manual grid placement" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_log 1"
          bot.wait_ticks 10

          bot.craft_pattern([["oak_log"]])
          bot.wait_ticks 10

          expect(bot.inventory.count("oak_planks")).to be >= 4
        end
      end
    end

    it "crafts a crafting table using manual 2x2 pattern" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/clear"
          bot.wait_ticks 5
          bot.chat "/give #{bot.username} minecraft:oak_planks 4"
          bot.wait_ticks 10

          bot.craft_pattern([
            ["oak_planks", "oak_planks"],
            ["oak_planks", "oak_planks"],
          ])
          bot.wait_ticks 10

          expect(bot.inventory.count("crafting_table")).to be >= 1
        end
      end
    end

    it "raises CraftingError when item not in inventory" do
      client.join_game do |client|
        Rosegold::Bot.new(client).try do |bot|
          bot.chat "/clear"
          bot.wait_ticks 10

          expect { bot.craft_pattern([["diamond", "diamond", "diamond"]]) }.to raise_error(Rosegold::Bot::CraftingError)
        end
      end
    end
  end
end
