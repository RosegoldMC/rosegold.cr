require "../spec_helper"

Spectator.describe Rosegold::Block do
  describe ".from_block_state_id" do
    it "finds the block from a block state id" do
      expect(Rosegold::Block.from_block_state_id(2040).id_str).to eq "oak_stairs"
      expect(Rosegold::Block.from_block_state_id(25).id_str).to eq "birch_sapling"
      expect(Rosegold::Block.from_block_state_id(1494).id_str).to eq "wall_torch"
      expect(Rosegold::Block.from_block_state_id(1496).id_str).to eq "fire"
      expect(Rosegold::Block.from_block_state_id(1500).id_str).to eq "fire"
      expect(Rosegold::Block.from_block_state_id(2007).id_str).to eq "fire"
      expect(Rosegold::Block.from_block_state_id(20341).id_str).to eq "potted_flowering_azalea_bush"
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
          expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 2  # dirt
        end
      end

      context "with a diamond pickaxe" do
        let(:main_hand) { Rosegold::Slot.new(item_id_int: 721) } # Diamond pickaxe

        it "calculates the break time properly with proper tool" do
          expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 6   # stone
          expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15 # dirt
        end

        context "with efficiency 4 enchantment" do
          let(:main_hand) {
            Rosegold::Slot.new(
              item_id_int: 721,
              nbt: Minecraft::NBT::CompoundTag.new(Hash(String, Minecraft::NBT::Tag).new.tap { |h|
                h["Enchantments"] = Minecraft::NBT::ListTag.new(Array(Minecraft::NBT::Tag).new.tap { |a|
                  a << Minecraft::NBT::CompoundTag.new(Hash(String, Minecraft::NBT::Tag).new.tap { |e|
                    e["id"] = Minecraft::NBT::StringTag.new("minecraft:efficiency")
                    e["lvl"] = Minecraft::NBT::ShortTag.new(4)
                  })
                })
              })
            )
          }

          it "calculates the break time properly with proper tool" do
            expect(Rosegold::Block.from_block_state_id(1490).break_time(main_hand, player)).to eq 60 # obsidian
            expect(Rosegold::Block.from_block_state_id(1).break_time(main_hand, player)).to eq 2     # stone
            expect(Rosegold::Block.from_block_state_id(10).break_time(main_hand, player)).to eq 15   # dirt
          end
        end
      end
    end
  end
end
