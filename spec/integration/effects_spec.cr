require "../spec_helper"

Spectator.describe "Rosegold::Bot effects" do
  it do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/effect clear #{bot.username}"
        bot.chat "/effect give #{bot.username} minecraft:haste 30 2"
        client.wait_for Rosegold::Clientbound::EntityEffect
        expect(client.player.effect_by_name("haste").try &.amplifier).to eq(2)

        bot.chat "/effect clear #{bot.username}"
      end
    end
  end
end
