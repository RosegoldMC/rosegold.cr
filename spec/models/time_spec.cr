require "../spec_helper"

Spectator.describe Rosegold::MCTime do
  it "should show local time correct" do
    time_zero = Rosegold::MCTime.new 24000
    expect(time_zero.local_time).to eq(0)
    time_thousand = Rosegold::MCTime.new 49000
    expect(time_thousand.local_time).to eq(1000)
  end

  it "should determine part of day correct" do
    sunrise = Rosegold::MCTime.new 0
    midnight = Rosegold::MCTime.new 18000

    expect(sunrise.is_day).to eq(true)
    expect(midnight.is_day).to eq(false)

    expect(midnight.is_night).to eq(true)
    expect(sunrise.is_night).to eq(false)
  end
end
