require "../spec_helper"

Spectator.describe Rosegold::Event::SneakChanged do
  it "is a subclass of Event" do
    expect(Rosegold::Event::SneakChanged.new(true)).to be_a Rosegold::Event
  end

  it "exposes the sneaking flag" do
    expect(Rosegold::Event::SneakChanged.new(true).sneaking?).to be_true
    expect(Rosegold::Event::SneakChanged.new(false).sneaking?).to be_false
  end
end
