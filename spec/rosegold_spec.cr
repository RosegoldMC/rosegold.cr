require "./spec_helper"

Spectator.describe Rosegold do
  it "should have a version" do
    expect(Rosegold::VERSION).to be_a(String)
  end

  it "should support configurable protocol version" do
    # Default is now 1.21.8 (protocol 772)
    expect(Rosegold::Client.protocol_version).to eq(772_u32)

    # Can be changed to 1.18
    Rosegold::Client.protocol_version = 758_u32
    expect(Rosegold::Client.protocol_version).to eq(758_u32)

    # Reset to default (1.21.6)
    Rosegold::Client.protocol_version = 771_u32
  end

  it "should support 1.18, 1.21, and 1.21.6 MCData" do
    expect { Rosegold::MCData.new("1.18") }.not_to raise_error
    expect { Rosegold::MCData.new("1.21") }.not_to raise_error
    expect { Rosegold::MCData.new("1.21.6") }.not_to raise_error
  end

  it "should reject unsupported versions" do
    expect { Rosegold::MCData.new("1.17") }.to raise_error(/we only support 1.18, 1.21, and 1.21.6/)
    expect { Rosegold::MCData.new("1.22") }.to raise_error(/we only support 1.18, 1.21, and 1.21.6/)
  end

  it "should default to 1.21.6 MCData" do
    expect(Rosegold::MCData::DEFAULT).to eq(Rosegold::MCData::MC1216)
  end
end
