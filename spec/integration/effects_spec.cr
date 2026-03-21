require "../spec_helper"

Spectator.describe "Rosegold::Bot effects" do
  it "should add and remove effects properly" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.effect_clear
        bot.wait_ticks 2

        expect(client.player.effect_by_name("haste")).to be_nil

        admin.effect_give "haste", 60, 2
        client.wait_for Rosegold::Clientbound::EntityEffect

        haste_effect = client.player.effect_by_name("haste")
        expect(haste_effect).to_not be_nil
        expect(haste_effect.try &.amplifier).to eq(2)

        admin.effect_clear
        client.wait_for Rosegold::Clientbound::RemoveEntityEffect

        expect(client.player.effect_by_name("haste")).to be_nil
      end
    end
  end
end
