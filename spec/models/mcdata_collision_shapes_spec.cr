require "../spec_helper"

Spectator.describe "MCData block collision shapes" do
  describe "block_state_collision_shapes" do
    it "has collision shapes for all block states" do
      max_state = Rosegold::MCData::DEFAULT.blocks.map(&.max_state_id).max
      expect(Rosegold::MCData::DEFAULT.block_state_collision_shapes.size).to eq(max_state + 1)
    end

    it "has correct collision shapes for air block" do
      air_state = 0_u16
      shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[air_state]
      expect(shapes).to be_empty
    end

    it "has correct collision shapes for solid blocks like stone" do
      stone_block = Rosegold::MCData::DEFAULT.blocks.find { |b| b.id_str == "stone" }
      stone_state = stone_block.not_nil!.default_state
      shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[stone_state]
      
      expect(shapes.size).to eq(1)
      # Full block should be 0,0,0 to 1,1,1
      expect(shapes[0].min.x).to eq(0.0_f32)
      expect(shapes[0].min.y).to eq(0.0_f32)
      expect(shapes[0].min.z).to eq(0.0_f32)
      expect(shapes[0].max.x).to eq(1.0_f32)
      expect(shapes[0].max.y).to eq(1.0_f32)
      expect(shapes[0].max.z).to eq(1.0_f32)
    end

    it "has collision shapes for cobblestone" do
      cobblestone_block = Rosegold::MCData::DEFAULT.blocks.find { |b| b.id_str == "cobblestone" }
      cobblestone_state = cobblestone_block.not_nil!.default_state
      shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[cobblestone_state]
      
      expect(shapes.size).to eq(1)
      # Full block collision
      expect(shapes[0].min.x).to eq(0.0_f32)
      expect(shapes[0].min.y).to eq(0.0_f32)
      expect(shapes[0].min.z).to eq(0.0_f32)
      expect(shapes[0].max.x).to eq(1.0_f32)
      expect(shapes[0].max.y).to eq(1.0_f32)
      expect(shapes[0].max.z).to eq(1.0_f32)
    end

    it "has collision shapes for dirt" do
      dirt_block = Rosegold::MCData::DEFAULT.blocks.find { |b| b.id_str == "dirt" }
      dirt_state = dirt_block.not_nil!.default_state
      shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[dirt_state]
      
      expect(shapes.size).to eq(1)
      # Full block collision
      expect(shapes[0].min.x).to eq(0.0_f32)
      expect(shapes[0].min.y).to eq(0.0_f32)
      expect(shapes[0].min.z).to eq(0.0_f32)
      expect(shapes[0].max.x).to eq(1.0_f32)
      expect(shapes[0].max.y).to eq(1.0_f32)
      expect(shapes[0].max.z).to eq(1.0_f32)
    end

    it "handles blocks with multiple states correctly" do
      # Find a block with multiple states
      block_with_states = Rosegold::MCData::DEFAULT.blocks.find { |b| !b.states.empty? }
      expect(block_with_states).not_to be_nil
      
      if block_with_states
        # Test all states of this block have collision shapes
        (block_with_states.min_state_id..block_with_states.max_state_id).each do |state_id|
          shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[state_id]
          expect(shapes).not_to be_nil
        end
      end
    end

    it "has non-empty collision shapes for common solid blocks" do
      solid_blocks = ["stone", "dirt", "cobblestone", "obsidian", "oak_planks"]
      
      solid_blocks.each do |block_name|
        block = Rosegold::MCData::DEFAULT.blocks.find { |b| b.id_str == block_name }
        next unless block # Skip if block doesn't exist
        
        shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[block.default_state]
        expect(shapes).not_to be_empty, "#{block_name} should have collision shapes"
        
        # All solid blocks should have at least one collision box
        expect(shapes.size).to be >= 1, "#{block_name} should have at least one collision box"
      end
    end

    it "has empty collision shapes for air-like blocks" do
      air_like_blocks = ["air", "water", "lava"]
      
      air_like_blocks.each do |block_name|
        block = Rosegold::MCData::DEFAULT.blocks.find { |b| b.id_str == block_name }
        next unless block # Skip if block doesn't exist
        
        shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[block.default_state]
        expect(shapes).to be_empty, "#{block_name} should have no collision shapes"
      end
    end

    it "has valid AABB coordinates (min <= max)" do
      # Test a sample of blocks to ensure AABBs are valid
      sample_blocks = Rosegold::MCData::DEFAULT.blocks.sample(10)
      
      sample_blocks.each do |block|
        shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[block.default_state]
        
        shapes.each do |aabb|
          expect(aabb.min.x).to be <= aabb.max.x, "#{block.id_str}: min.x should be <= max.x"
          expect(aabb.min.y).to be <= aabb.max.y, "#{block.id_str}: min.y should be <= max.y"
          expect(aabb.min.z).to be <= aabb.max.z, "#{block.id_str}: min.z should be <= max.z"
        end
      end
    end

    it "can look up collision shapes for high state IDs" do
      # Test blocks with high state IDs to ensure the array is properly sized
      high_state_blocks = Rosegold::MCData::DEFAULT.blocks.select { |b| b.max_state_id > 20000 }
      
      expect(high_state_blocks).not_to be_empty, "Should have blocks with high state IDs"
      
      high_state_blocks.first(3).each do |block|
        shapes = Rosegold::MCData::DEFAULT.block_state_collision_shapes[block.default_state]
        expect(shapes).not_to be_nil, "#{block.id_str} should have collision shapes array"
      end
    end
  end
end