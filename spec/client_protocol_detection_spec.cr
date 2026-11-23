require "./spec_helper"

class ProtocolDetectionSpecClient < Rosegold::Client
  property advertised : Int32 = 0

  def initialize
    super("localhost", offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "detect"})
  end

  def status
    Rosegold::Clientbound::StatusResponse.new JSON.parse(%({"version":{"protocol":#{advertised}}}))
  end

  def detect
    detect_protocol_version
  end
end

Spectator.describe "Client protocol detection" do
  after_each { Rosegold::Client.reset_protocol_version! }

  let(client) { ProtocolDetectionSpecClient.new }
  let(older) { Rosegold::Client::SUPPORTED_PROTOCOLS.reject { |protocol| protocol == Rosegold::Client::LATEST_PROTOCOL }.last }

  it "stores a detected protocol on the base Client from a subclass" do
    client.advertised = older.to_i
    client.detect
    expect(Rosegold::Client.protocol_version).to eq older
    expect(client.protocol_version).to eq older
    expect(Rosegold::Client.protocol_version_explicit?).to be_false
  end

  it "stores the fallback on the base Client for unsupported servers" do
    client.advertised = older.to_i
    client.detect
    expect(Rosegold::Client.protocol_version).to eq older

    client.advertised = 1
    client.detect
    expect(Rosegold::Client.protocol_version).to eq Rosegold::Client::LATEST_PROTOCOL
    expect(Rosegold::Client.protocol_version_explicit?).to be_false
  end

  it "keeps an explicit version" do
    Rosegold::Client.protocol_version = older
    client.advertised = Rosegold::Client::LATEST_PROTOCOL.to_i
    client.detect
    expect(Rosegold::Client.protocol_version).to eq older
    expect(Rosegold::Client.protocol_version_explicit?).to be_true
  end
end
