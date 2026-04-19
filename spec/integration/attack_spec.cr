require "../spec_helper"

def zombie_entity_type
  Rosegold::Entity.metadata_for_protocol.find! { |meta| meta.name == "zombie" }.id.to_u32
end

Spectator.describe "Rosegold::Bot attack" do
  after_all do
    admin.setup_arena
    admin.wait_tick
  end

  it "should be able to attack even if the target is moving" do
    admin.setup_arena
    admin.wait_ticks 5
    admin.time_set 13000
    admin.fill -10, -60, 8, 0, -58, 6, "obsidian"
    admin.fill -9, -60, 7, 0, -58, 7, "air"
    admin.wait_tick
    admin.fill -6, -60, 7, -6, -60, 7, "water"
    admin.wait_tick
    admin.fill -9, -59, 8, -9, -59, 8, "air"
    admin.wait_tick
    admin.chat "/kill @e[type=zombie]"
    admin.wait_tick
    admin.summon "zombie", -7, -60, 7
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp -9, -60, 9
        admin.clear
        admin.give "diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        admin.effect_give "strength", 60, 2
        bot.wait_ticks 5

        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0

        # Wait for zombie entity to appear in client's entity list
        20.times do
          break if client.dimension_for_test.entities.any? { |_, e| e.entity_type == zombie_entity_type }
          bot.wait_ticks 2
        end

        30.times do
          break if client.dimension_for_test.entities.select { |_, e| e.entity_type == zombie_entity_type }.empty?
          bot.attack
          bot.wait_ticks 13
        end
        # no zombies left
        expect(client.dimension_for_test.entities.select { |_, e| e.entity_type == zombie_entity_type }).to be_empty
      end
    end
  end

  it "should not be able to attack entities through blocks" do
    admin.setup_arena
    admin.wait_ticks 5
    admin.time_set 13000
    admin.fill -10, -60, 8, 0, -58, 6, "obsidian"
    admin.fill -9, -60, 7, 0, -58, 7, "air"
    admin.wait_tick
    admin.fill -6, -60, 7, -6, -60, 7, "water"
    admin.wait_tick
    admin.chat "/kill @e[type=zombie]"
    admin.wait_tick
    admin.summon "zombie", -7, -60, 7
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp -9, -60, 9
        admin.clear
        admin.give "diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        admin.effect_give "strength", 60, 2
        bot.wait_ticks 5
        bot.inventory.pick! "diamond_sword"

        # Aim towards the zombie (south, towards negative Z)
        bot.yaw = 180.0 # South (towards the zombie at Z=7 from bot at Z=9)
        bot.pitch = 0.0 # Level

        # Wait for zombie SpawnEntity packet to arrive
        20.times do
          break if client.dimension_for_test.entities.any? { |_, e| e.entity_type == zombie_entity_type }
          bot.wait_ticks 2
        end

        # Additional verification: count zombies before attack
        zombies_before = client.dimension_for_test.entities.count { |_, e| e.entity_type == zombie_entity_type }
        expect(zombies_before).to eq(1) # Ensure zombie is present

        # Try to attack multiple times - should not hit the zombie through the block
        10.times do # Increased from 5 to ensure zombie would definitely die if hit
          bot.attack
          bot.wait_ticks 5
        end

        # Wait a bit more to ensure any delayed effects are processed
        bot.wait_ticks 10

        # Count zombies after attack - should be the same (zombie should still be alive)
        zombies_after = client.dimension_for_test.entities.count { |_, e| e.entity_type == zombie_entity_type }

        # The zombie should still be alive because the block prevented the attack
        expect(zombies_after).to eq(zombies_before)
        expect(zombies_after).to eq(1)
      end
    end
  end
end
