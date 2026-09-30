require "./spec_helper"

class BotApiSpecBot < Rosegold::Bot
  getter aimed_at : Rosegold::Look?
  property heights = [] of Float64
  getter waited_ticks = 0

  def chat(message : String)
    raise "send failed"
  end

  def look=(target : Rosegold::Look)
    @aimed_at = target
  end

  def wait_tick
    @waited_ticks += 1
    if height = heights.shift?
      @client.player.feet = Rosegold::Vec3d.new(0.0, height, 0.0)
    end
  end
end

Spectator.describe Rosegold::Bot do
  let(:client) {
    Rosegold::Client.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "test"})
  }
  let(:bot) { BotApiSpecBot.new(client) }

  it "constructs from an address without connecting" do
    unconnected = Rosegold::Bot.new("localhost")
    expect(unconnected.host).to eq("localhost")
    expect(unconnected.connected?).to be_falsey
  end

  it "accepts the first and last one-based hotbar slots" do
    bot.hotbar_selection = 1_u8
    expect(client.player.hotbar_selection).to eq(0)
    bot.hotbar_selection = 9_u8
    expect(client.player.hotbar_selection).to eq(8)
  end

  it "rejects hotbar slots outside 1 through 9 without changing selection" do
    bot.hotbar_selection = 5_u8
    expect { bot.hotbar_selection = 0_u8 }.to raise_error(ArgumentError)
    expect { bot.hotbar_selection = 10_u8 }.to raise_error(ArgumentError)
    expect(bot.hotbar_selection).to eq(5)
  end

  it "accepts Look targets for digging" do
    bot.start_digging Rosegold::Look::NORTH
    expect(bot.aimed_at).to eq(Rosegold::Look::NORTH)
  end

  it "recognizes stable height after descending" do
    client.player.feet = Rosegold::Vec3d.new(0.0, 3.0, 0.0)
    bot.heights = [2.0, 1.0, 1.0]
    bot.land_on_ground(5)
    expect(bot.waited_ticks).to eq(3)
  end

  it "times out while height keeps changing" do
    client.player.feet = Rosegold::Vec3d.new(0.0, 5.0, 0.0)
    bot.heights = [4.0, 3.0, 2.0]
    expect { bot.land_on_ground(3) }.to raise_error(Exception, /Still falling/)
  end

  it "raises when a jump never reaches its requested height" do
    bot.heights = [0.2, 0.4, 0.6]
    expect { bot.jump_by_height(1, 3) }.to raise_error(Exception, /within 3 ticks/)
  end

  it "returns after a jump reaches the requested height" do
    bot.heights = [0.4, 1.0]
    bot.jump_by_height(1, 3)
    expect(bot.waited_ticks).to eq(2)
  end

  it "removes command confirmation listeners if sending raises" do
    expect do
      bot.run_command_with_confirmation("/example", "done")
    end.to raise_error(Exception, "send failed")
    expect(bot.event_handlers[Rosegold::Clientbound::SystemChatMessage]).to be_empty
  end
end
