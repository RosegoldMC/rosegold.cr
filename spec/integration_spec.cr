require "./spec_helper"

Spectator.describe Rosegold::Client do
  it "should connect to a running server" do
    Rosegold::Client.new("localhost", 25565).start
  end
end
