require "../spec_helper"
require "log/spec"

Spectator.describe "Rosegold::Client disconnection" do
  it "should handle disconnection via kick command" do
    client.join_game do |client|
      disconnect_event = client.wait_for(Rosegold::Event::Disconnected, timeout: 5.seconds) do
        admin.chat "/kick #{AdminBot::TEST_PLAYER}"
      end

      expect(disconnect_event).to_not be_nil
      expect(disconnect_event.try(&.reason)).to_not be_nil
    end
  end

  it "should log disconnect reason clearly without IO error" do
    Log.capture("rosegold") do |logs|
      begin
        client.join_game do |client|
          client.wait_for(Rosegold::Event::Disconnected, timeout: 5.seconds) do
            admin.chat "/kick #{AdminBot::TEST_PLAYER}"
          end
        end
      rescue Rosegold::Client::NotConnected
      end

      logs.check(:info, /Disconnected:.*Kicked/i)
    end
  end
end
