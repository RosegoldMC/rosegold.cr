require "./spec_helper"

Spectator.describe Rosegold::ReconnectPolicy do
  let(policy) { Rosegold::ReconnectPolicy.new }

  it "caps ordinary reconnect backoff at five minutes" do
    delays = Array.new(9) { policy.next_delay }

    expect(delays).to eq([
      10.seconds, 20.seconds, 40.seconds, 80.seconds, 160.seconds,
      5.minutes, 5.minutes, 5.minutes, 5.minutes,
    ])
  end

  it "retains ordinary backoff when joining fails or a joined session ends too soon" do
    expect(policy.next_delay).to eq(10.seconds)
    expect(policy.next_delay(connected_for: 9.seconds)).to eq(20.seconds)
    expect(policy.next_delay).to eq(40.seconds)
    expect(policy.next_delay(connected_for: 39.seconds)).to eq(80.seconds)
  end

  it "resets ordinary backoff after a healthy joined session" do
    3.times { policy.next_delay }

    expect(policy.next_delay(connected_for: 40.seconds)).to eq(10.seconds)
    expect(policy.next_delay).to eq(20.seconds)
  end

  it "uses capped provider cooldowns for forbidden and rate-limited responses" do
    [403, 429].each do |status|
      error = Minecraft::AuthenticationError.new("Rejected", phase: "provider_#{status}", status_code: status)
      delays = Array.new(5) { policy.next_delay(error) }

      expect(delays).to eq([5.minutes, 10.minutes, 15.minutes, 15.minutes, 15.minutes])
    end
  end

  it "uses capped transport cooldowns for unavailable authentication providers" do
    error = Minecraft::AuthenticationError.new("Unavailable", phase: "xsts", status_code: 503, transient: true)

    expect(Array.new(7) { policy.next_delay(error) }).to eq([
      1.minute, 2.minutes, 4.minutes, 8.minutes, 15.minutes, 15.minutes, 15.minutes,
    ])
  end

  it "backs off authentication transport failures without a response status" do
    error = Minecraft::AuthenticationError.new("Connection closed", phase: "minecraft_login", transient: true)

    expect(policy.next_delay(error)).to eq(1.minute)
    expect(policy.next_delay(error)).to eq(2.minutes)
  end

  it "honors Retry-After as a floor even beyond the usual cap" do
    short = Minecraft::AuthenticationError.new("Rate limited", phase: "xsts", status_code: 429, retry_after: 30.seconds)
    long = Minecraft::AuthenticationError.new("Rate limited", phase: "xsts", status_code: 429, retry_after: 1.hour)

    expect(policy.next_delay(short)).to eq(5.minutes)
    expect(policy.next_delay(long)).to eq(1.hour)
    expect(policy.next_delay(short)).to eq(15.minutes)
  end

  it "tracks failures separately and clears only the successful authentication phase" do
    xbox = Minecraft::AuthenticationError.new("Rejected", phase: "xbox_live", status_code: 403)
    xsts = Minecraft::AuthenticationError.new("Rejected", phase: "xsts", status_code: 403)
    2.times { policy.next_delay(xbox) }
    2.times { policy.next_delay(xsts) }

    policy.record_auth_success("xbox_live")

    expect(policy.next_delay(xbox)).to eq(5.minutes)
    expect(policy.next_delay(xsts)).to eq(15.minutes)
  end

  it "keeps authentication cooldowns after a healthy joined session" do
    error = Minecraft::AuthenticationError.new("Rate limited", phase: "session_join", status_code: 429)
    policy.next_delay(error)
    policy.next_delay
    policy.next_delay(connected_for: 10.minutes)

    expect(policy.next_delay(error)).to eq(10.minutes)
  end

  it "quickly refreshes a rejected cached token without advancing either failure streak" do
    error = Minecraft::AuthenticationError.new("Rejected", phase: "session_join", status_code: 403)
    cached = Minecraft::AuthenticationError.new("Cached token rejected", phase: "session_join", status_code: 403,
      refresh_cached_token: true)
    policy.next_delay
    policy.next_delay(error)

    expect(policy.next_delay(cached)).to eq(10.seconds)
    expect(policy.next_delay(error)).to eq(10.minutes)
    expect(policy.next_delay).to eq(20.seconds)
  end
end
