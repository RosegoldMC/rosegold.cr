require "./spec_helper"

Spectator.describe Rosegold do
  it "should have a version" do
    expect(Rosegold::VERSION).to be_a(String)
  end
end
