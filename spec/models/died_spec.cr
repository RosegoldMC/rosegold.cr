require "../spec_helper"

Spectator.describe Rosegold::Event::Died do
  it "is a subclass of Event" do
    event = Rosegold::Event::Died.new
    expect(event).to be_a Rosegold::Event
  end

  it "can be instantiated with no arguments" do
    expect { Rosegold::Event::Died.new }.not_to raise_error
  end
end
