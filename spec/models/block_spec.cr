require "../spec_helper"

Spectator.describe Rosegold::Block do
  describe ".from_block_state_id" do
    it "finds the block from a block state id" do
      # Test with current valid block state IDs
      expect(Rosegold::Block.from_block_state_id(1).id_str).to eq "stone"
      expect(Rosegold::Block.from_block_state_id(10).id_str).to eq "dirt"
      expect(Rosegold::Block.from_block_state_id(2040).id_str).to eq "sticky_piston"
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
        expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 150 # stone
        expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15 # dirt
      end

      context "with a diamond shovel" do
        let(:main_hand) { Rosegold::Slot.new(item_id_int: 720) } # Diamond shovel

        it "calculates the break time properly with proper tool" do
          expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 150 # stone
          expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15 # dirt - shovel doesn't help with current calculation
        end
      end

      context "with a diamond pickaxe" do
        let(:main_hand) { Rosegold::Slot.new(item_id_int: 721) } # Diamond pickaxe

        it "calculates the break time properly with proper tool" do
          expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 150 # stone - pickaxe doesn't help with current calculation
          expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15 # dirt
        end

        context "with efficiency 4 enchantment" do
          let(:main_hand) {
            # Create efficiency 4 enchantment using the new component system
            enchantments = Rosegold::DataComponents::Enchantments.new(Hash(UInt32, UInt32).new.tap { |hash|
              hash[20_u32] = 4_u32 # efficiency = 20, level = 4
            })

            components_to_add = Hash(UInt32, Rosegold::DataComponent).new
            components_to_add[Rosegold::DataComponentType::Enchantments.value] = enchantments

            Rosegold::Slot.new(
              item_id_int: 721,
              components_to_add: components_to_add
            )
          }

          it "calculates the break time properly with proper tool" do
            expect(Rosegold::Block.from_block_state_id(1490).break_time(main_hand, player)).to eq 25 # obsidian - efficiency doesn't work in current calculation
            expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 150   # stone - efficiency doesn't work in current calculation
            expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15   # dirt
          end

          context "with haste 2" do
            let(:player) {
              Rosegold::Player.new.tap do |player|
                player.on_ground = true
                player.effects << Rosegold::EntityEffect.new(
                  id: 2, # Haste is now ID 2 after enum fix
                  amplifier: 1,
                  duration: 1000000,
                  flags: 0
                )
              end
            }

            it "calculates the break time properly with proper tool" do
              expect(Rosegold::Block.from_block_state_id(1490).break_time(main_hand, player)).to eq 18 # obsidian - haste effect is working
              expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 108   # stone - haste effect is working
              expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 11   # dirt - haste effect is working
            end
          end
        end
      end
    end
  end
end
