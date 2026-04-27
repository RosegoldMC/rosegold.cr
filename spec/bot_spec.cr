require "./spec_helper"

Spectator.describe Rosegold::Bot do
  describe "#estimated_break_ticks" do
    let(:client) {
      c = Rosegold::Client.new("localhost", 25565,
        offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldtest"})
      c.player.on_ground = true
      c
    }
    let(:bot) { Rosegold::Bot.new(client) }

    it "estimates break ticks for a known block, including the default buffer" do
      # bare-handed stone takes 150 ticks; default buffer is 10
      expect(bot.estimated_break_ticks("stone")).to eq(160)
    end

    it "honors a custom buffer_ticks kwarg" do
      expect(bot.estimated_break_ticks("stone", buffer_ticks: 0)).to eq(150)
      expect(bot.estimated_break_ticks("stone", buffer_ticks: 25)).to eq(175)
    end

    it "factors in the bot's live status effects" do
      client.player.effects << Rosegold::EntityEffect.new(
        id: 2, # Haste
        amplifier: 1,
        duration: 1_000_000,
        flags: 0
      )
      # bare-handed dirt is 15 ticks; with Haste 2 it drops to 11
      expect(bot.estimated_break_ticks("dirt", buffer_ticks: 0)).to eq(11)
    end

    it "factors in the bot's airborne state" do
      client.player.on_ground = false
      # bare-handed dirt on the ground is 15 ticks; airborne mining is 5x slower
      expect(bot.estimated_break_ticks("dirt", buffer_ticks: 0)).to eq(75)
    end

    it "raises ArgumentError on an unknown block name" do
      expect { bot.estimated_break_ticks("not_a_real_block") }.to raise_error(ArgumentError)
    end
  end
end
