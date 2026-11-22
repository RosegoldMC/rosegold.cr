require "../spec_helper"

Spectator.describe "Rosegold::Bot mounted attacks" do
  it "attacks a nearby pig while riding a minecart" do
    admin.chat "/kill @e[tag=mounted_attack_spec]"
    admin.fill 0, -60, 0, 4, -58, 1, "air"
    admin.fill 0, -61, 0, 4, -61, 1, "stone"
    admin.setblock 0, -60, 0, "rail[shape=north_south]"
    admin.chat "/summon minecraft:minecart 0.5 -59.9375 0.5 {Tags:[\"mounted_attack_spec\"]}"
    pig_position = Rosegold::Vec3d.new(2.5, -60.0, 0.5)
    admin.chat "/summon minecraft:pig #{pig_position.x} #{pig_position.y} #{pig_position.z} {NoAI:1b,Tags:[\"mounted_attack_spec\"]}"
    admin.wait_ticks 5

    client.join_game do |client|
      bot = Rosegold::Bot.new(client)
      begin
        admin.tp 0.5, -60, 0.5
        admin.clear
        admin.give "diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        admin.effect_give "strength", 60, 2
        bot.wait_ticks 5
        bot.inventory.pick! "diamond_sword"
        admin.chat "/ride #{AdminBot::TEST_PLAYER} mount @e[type=minecraft:minecart,tag=mounted_attack_spec,limit=1]"

        40.times do
          break if bot.riding?("minecart")
          bot.wait_tick
        end
        expect(bot.riding?("minecart")).to be_true

        pig = nil
        40.times do
          pig = bot.nearest_entity(max_distance: 5) { |entity| entity.type == "pig" && entity.position == pig_position }
          break if pig
          bot.wait_tick
        end
        pig_id = pig.try(&.id) || raise "Fixture pig is not loaded"

        bot.look = Rosegold::Look.new(-90_f32, 12.5_f32)
        bot.wait_ticks 5

        10.times do
          break unless bot.entity(pig_id)
          bot.attack
          bot.wait_ticks 13
        end

        expect(bot.entity(pig_id)).to be_nil
        expect(bot.riding?("minecart")).to be_true
      ensure
        admin.chat "/ride #{AdminBot::TEST_PLAYER} dismount"
        admin.chat "/kill @e[tag=mounted_attack_spec]"
        admin.chat "/effect clear #{AdminBot::TEST_PLAYER} minecraft:strength"
        admin.clear
        admin.fill 0, -60, 0, 4, -58, 1, "air"
        admin.wait_ticks 5
      end
    end
  end
end
