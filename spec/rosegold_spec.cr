require "./spec_helper"

Spectator.describe Rosegold do
  it "should have a version" do
    expect(Rosegold::VERSION).to be_a(String)
  end

  it "should have default protocol version 772" do
    # Default is 1.21.8 (protocol 772)
    expect(Rosegold::Client.protocol_version).to eq(772_u32)
  end

  it "should support 1.21.8 MCData" do
    expect { Rosegold::MCData.new("1.21.8") }.not_to raise_error
  end

  it "should reject unsupported versions" do
    expect { Rosegold::MCData.new("1.17") }.to raise_error(/Rosegold.cr only supports 1.21.8 for now/)
    expect { Rosegold::MCData.new("1.22") }.to raise_error(/Rosegold.cr only supports 1.21.8 for now/)
  end

  it "should default to 1.21.8 MCData" do
    expect(Rosegold::MCData::DEFAULT).to eq(Rosegold::MCData::MC1218)
  end
end
