require "../spec_helper"

Spectator.describe Rosegold::Event::HealthChanged do
  it "stores all fields" do
    event = Rosegold::Event::HealthChanged.new(20.0_f32, 10.0_f32, 20_u32, 5.0_f32)
    expect(event).to be_a Rosegold::Event
    expect(event.old_health).to eq 20.0_f32
    expect(event.health).to eq 10.0_f32
    expect(event.food).to eq 20_u32
    expect(event.saturation).to eq 5.0_f32
  end
end
