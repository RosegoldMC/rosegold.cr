require "../spec_helper"

Spectator.describe "Automatic reconnection" do
  it "joins with a fresh bot after a server kick and stops on explicit disconnect" do
    sessions = [] of Rosegold::Bot
    offline = {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldtest"}

    Rosegold::Bot.run(MC_TEST_HOST, MC_TEST_PORT, offline: offline) do |bot|
      sessions << bot
      if sessions.size == 1
        bot.client.wait_for(Rosegold::Event::Disconnected, timeout: 5.seconds) do
          admin.chat "/kick #{AdminBot::TEST_PLAYER}"
        end
      else
        expect(bot.spawned?).to be_truthy
        bot.disconnect("Reconnect test finished")
      end
    end

    expect(sessions.size).to eq(2)
    expect(sessions.first.client).not_to be(sessions.last.client)
    expect(sessions.all? { |bot| !bot.connected? }).to be_true
    select
    when sessions.first.client.ticker_done.receive
    when timeout(1.second)
      raise "Previous session ticker did not finish"
    end
  end
end
