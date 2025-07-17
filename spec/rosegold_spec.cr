require "./spec_helper"

Spectator.describe Rosegold do
  it "should have a version" do
    expect(Rosegold::VERSION).to be_a(String)
  end

  it "should support configurable protocol version" do
    # Default is now 1.21 (protocol 767)
    expect(Rosegold::Client.protocol_version).to eq(767_u32)

    # Can be changed to 1.18
    Rosegold::Client.protocol_version = 758_u32
    expect(Rosegold::Client.protocol_version).to eq(758_u32)

    # Reset to default (1.21)
    Rosegold::Client.protocol_version = 767_u32
  end

  it "should support both 1.18 and 1.21 MCData" do
    expect { Rosegold::MCData.new("1.18") }.not_to raise_error
    expect { Rosegold::MCData.new("1.21") }.not_to raise_error
  end

  it "should reject unsupported versions" do
    expect { Rosegold::MCData.new("1.17") }.to raise_error(/we only support 1.18 and 1.21/)
    expect { Rosegold::MCData.new("1.22") }.to raise_error(/we only support 1.18 and 1.21/)
  end

  it "should default to 1.21 MCData" do
    expect(Rosegold::MCData::DEFAULT).to eq(Rosegold::MCData::MC121)
  end
end
