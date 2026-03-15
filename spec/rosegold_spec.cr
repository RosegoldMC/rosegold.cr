require "./spec_helper"

Spectator.describe Rosegold do
  it "should have a version" do
    expect(Rosegold::VERSION).to be_a(String)
  end

  it "should have a valid default protocol version" do
    expect(Rosegold::Client.protocol_version).to be >= 772_u32
  end

  it "should support 1.21.8 MCData" do
    expect { Rosegold::MCData.new("1.21.8") }.not_to raise_error
  end

  it "should support 1.21.11 MCData" do
    expect { Rosegold::MCData.new("1.21.11") }.not_to raise_error
  end

  it "should reject unsupported versions" do
    expect { Rosegold::MCData.new("1.17") }.to raise_error
    expect { Rosegold::MCData.new("1.22") }.to raise_error
  end

  it "should have a valid default MCData" do
    expect(Rosegold::MCData.default).not_to be_nil
  end
end
