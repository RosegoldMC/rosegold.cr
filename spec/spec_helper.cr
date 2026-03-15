require "../src/rosegold"
require "spectator"

MC_TEST_HOST = ENV["MC_TEST_HOST"]? || "localhost"
MC_TEST_PORT = (ENV["MC_TEST_PORT"]? || "25565").to_i

def client
  Rosegold::Client.new(MC_TEST_HOST, MC_TEST_PORT, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldtest"})
end

Spectator.configure do |config|
  config.formatter = Spectator::Formatting::DocumentFormatter.new
end
