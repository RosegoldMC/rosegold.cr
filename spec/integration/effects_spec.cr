require "../spec_helper"

Spectator.describe "Rosegold::Bot effects" do
  it "should add and remove effects properly" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/effect clear #{bot.username}"
        bot.wait_ticks 2
        
        # Verify no haste effect initially
        expect(client.player.effect_by_name("haste")).to be_nil
        
        # Apply haste effect for longer duration (60 seconds)
        bot.chat "/effect give #{bot.username} minecraft:haste 60 2"
        client.wait_for Rosegold::Clientbound::EntityEffect
        
        # Verify haste was added to the player
        haste_effect = client.player.effect_by_name("haste")
        expect(haste_effect).to_not be_nil
        expect(haste_effect.try &.amplifier).to eq(2)
        
        # Manually clear effects to test removal
        bot.chat "/effect clear #{bot.username}"
        client.wait_for Rosegold::Clientbound::RemoveEntityEffect
        
        # Verify haste effect was removed
        expect(client.player.effect_by_name("haste")).to be_nil
      end
    end
  end
end
