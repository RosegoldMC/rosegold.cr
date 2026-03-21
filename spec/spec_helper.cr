require "../src/rosegold"
require "spectator"
require "./support/admin_bot"

MC_TEST_HOST = ENV["MC_TEST_HOST"]? || "localhost"
MC_TEST_PORT = (ENV["MC_TEST_PORT"]? || "25565").to_i

def client
  Rosegold::Client.new(MC_TEST_HOST, MC_TEST_PORT, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldtest"})
end

def admin
  AdminBot.lazy_instance(MC_TEST_HOST, MC_TEST_PORT)
end

at_exit { AdminBot.shutdown }

Spectator.configure do |config|
  config.formatter = Spectator::Formatting::DocumentFormatter.new
end
