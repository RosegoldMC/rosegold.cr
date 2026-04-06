require "../spec_helper"

Spectator.describe Rosegold::Block do
  # Dynamic lookups — IDs shift between MC versions
  let(:mcdata) { Rosegold::MCData.default }
  let(:stone_state) { mcdata.blocks.find! { |block| block.id_str == "stone" }.min_state_id }
  let(:dirt_state) { mcdata.blocks.find! { |block| block.id_str == "dirt" }.min_state_id }
  let(:obsidian_state) { mcdata.blocks.find! { |block| block.id_str == "obsidian" }.min_state_id }
  let(:diamond_shovel_id) { mcdata.items.find! { |i| i.name == "diamond_shovel" }.id }
  let(:diamond_pickaxe_id) { mcdata.items.find! { |i| i.name == "diamond_pickaxe" }.id }
  let(:efficiency_id) { mcdata.enchantments.find! { |e| e.name == "efficiency" }.id }

  describe ".from_block_state_id" do
    it "finds the block from a block state id" do
      sticky_piston = mcdata.blocks.find! { |block| block.id_str == "sticky_piston" }
      expect(Rosegold::Block.from_block_state_id(stone_state).id_str).to eq "stone"
      expect(Rosegold::Block.from_block_state_id(dirt_state).id_str).to eq "dirt"
      expect(Rosegold::Block.from_block_state_id(sticky_piston.min_state_id).id_str).to eq "sticky_piston"
    end
  end

  describe "#break_time" do
    context "when holding nothing" do
      let(:main_hand) { Rosegold::Slot.new }
      let(:player) {
        Rosegold::Player.new.tap do |player|
          player.on_ground = true
        end
      }

      it "calculates the break time properly" do
        expect(Rosegold::Block.from_block_state_id(stone_state).break_time(main_hand, player)).to eq 150 # stone
        expect(Rosegold::Block.from_block_state_id(dirt_state).break_time(main_hand, player)).to eq 15   # dirt
      end

      context "with a diamond shovel" do
        let(:main_hand) { Rosegold::Slot.new(item_id_int: diamond_shovel_id) }

        it "calculates the break time properly with proper tool" do
          expect(Rosegold::Block.from_block_state_id(stone_state).break_time(main_hand, player)).to eq 150 # stone — shovel is wrong tool
          expect(Rosegold::Block.from_block_state_id(dirt_state).break_time(main_hand, player)).to eq 2    # dirt — shovel is correct tool
        end
      end

      context "with a diamond pickaxe" do
        let(:main_hand) { Rosegold::Slot.new(item_id_int: diamond_pickaxe_id) }

        it "calculates the break time properly with proper tool" do
          expect(Rosegold::Block.from_block_state_id(stone_state).break_time(main_hand, player)).to eq 6 # stone — pickaxe is correct tool
          expect(Rosegold::Block.from_block_state_id(dirt_state).break_time(main_hand, player)).to eq 15 # dirt — pickaxe is wrong tool, same as bare hands
        end

        context "with efficiency 4 enchantment" do
          let(:main_hand) {
            enchantments = Rosegold::DataComponents::Enchantments.new(Hash(UInt32, UInt32).new.tap { |hash|
              hash[efficiency_id] = 4_u32
            })

            components_to_add = Hash(String, Rosegold::DataComponent).new
            components_to_add["enchantments"] = enchantments

            Rosegold::Slot.new(
              item_id_int: diamond_pickaxe_id,
              components_to_add: components_to_add
            )
          }

          it "calculates the break time properly with proper tool" do
            expect(Rosegold::Block.from_block_state_id(obsidian_state).break_time(main_hand, player)).to eq 60 # obsidian
            expect(Rosegold::Block.from_block_state_id(stone_state).break_time(main_hand, player)).to eq 2     # stone
            expect(Rosegold::Block.from_block_state_id(dirt_state).break_time(main_hand, player)).to eq 15     # dirt — efficiency doesn't apply (speed not > 1.0)
          end

          context "with haste 2" do
            let(:player) {
              Rosegold::Player.new.tap do |player|
                player.on_ground = true
                player.effects << Rosegold::EntityEffect.new(
                  id: 2, # Haste
                  amplifier: 1,
                  duration: 1000000,
                  flags: 0
                )
              end
            }

            it "calculates the break time properly with proper tool" do
              expect(Rosegold::Block.from_block_state_id(obsidian_state).break_time(main_hand, player)).to eq 43 # obsidian
              expect(Rosegold::Block.from_block_state_id(stone_state).break_time(main_hand, player)).to eq 2     # stone
              expect(Rosegold::Block.from_block_state_id(dirt_state).break_time(main_hand, player)).to eq 11     # dirt — haste applies but efficiency doesn't
            end
          end
        end
      end
    end
  end
end
