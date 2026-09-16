require "../spec_helper"

Spectator.describe Rosegold::Event::ArmSwing do
  it "preserves the existing hand-only API" do
    event = described_class.new(Rosegold::Hand::OffHand)

    expect(event.hand).to eq(Rosegold::Hand::OffHand)
    expect(event.animation).to be_nil
  end

  it "carries an optional animation" do
    animation = Rosegold::DataComponents::SwingAnimation.new(2_u32, 13_u32)
    event = described_class.new(Rosegold::Hand::MainHand, animation)

    expect(event.animation).to eq(animation)
  end
end
