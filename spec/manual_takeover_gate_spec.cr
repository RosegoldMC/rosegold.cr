require "./spec_helper"

class GateSpecClient < Rosegold::Client
  def physics_for_test
    physics
  end
end

Spectator.describe "Manual control gate for inventory pick and jump" do
  let(client) { GateSpecClient.new("localhost") }
  let(bot) { Rosegold::Bot.new(client) }

  it "does not select a slot when control is taken while the predicate runs" do
    client.player.hotbar_selection = 0_u8
    client.inventory_menu.slots[37] = Rosegold::WindowSlot.new(37, Rosegold::Slot.new(1_u32, Rosegold::MCData.default.items.find! { |item| item.name == "stone" }.id.to_u32))
    granted = false
    result = bot.inventory.pick do |slot|
      unless granted
        granted = true
        client.manual_control.grant
      end
      slot.name == "stone"
    end

    expect(result).to be_false
    expect(client.player.hotbar_selection).to eq 0_u8
  end

  it "does not clear a queued jump through stop_jump while control is granted" do
    client.manual_control.grant
    client.physics_for_test.jump_queued = true

    bot.stop_jump

    expect(client.physics_for_test.jump_queued?).to be_true
  end
end
