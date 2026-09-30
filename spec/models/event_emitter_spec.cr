require "../spec_helper"

Spectator.describe Rosegold::EventEmitter do
  let(:emitter) { Rosegold::EventEmitter.new }

  it "removes a timed-out listener without removing other subscriptions" do
    calls = 0
    emitter.on(Rosegold::Event::Tick) { calls += 1 }
    expect(emitter.wait_for(Rosegold::Event::Tick, timeout: 0.seconds)).to be_nil
    expect(emitter.event_handlers[Rosegold::Event::Tick].size).to eq(1)
    emitter.emit_event Rosegold::Event::Tick.new
    expect(calls).to eq(1)
  end

  it "registers before running the triggering block and returns its event" do
    event = Rosegold::Event::Tick.new
    result = emitter.wait_for(Rosegold::Event::Tick) { emitter.emit_event event }
    expect(result).to eq(event)
    expect(emitter.event_handlers[Rosegold::Event::Tick]).to be_empty
  end

  it "removes the listener when the triggering block raises" do
    expect do
      emitter.wait_for(Rosegold::Event::Tick) { raise "action failed" }
    end.to raise_error(Exception, "action failed")
    expect(emitter.event_handlers[Rosegold::Event::Tick]).to be_empty
  end

  it "removes the listener when a triggered wait times out" do
    expect do
      emitter.wait_for(Rosegold::Event::Tick, timeout: 0.seconds) { nil }
    end.to raise_error(Exception, /Timed out waiting/)
    expect(emitter.event_handlers[Rosegold::Event::Tick]).to be_empty
  end

  it "removes a once handler before a recursive emission" do
    calls = 0
    emitter.once Rosegold::Event::Tick do |_event|
      calls += 1
      emitter.emit_event Rosegold::Event::Tick.new if calls == 1
    end
    emitter.emit_event Rosegold::Event::Tick.new
    expect(calls).to eq(1)
  end

  it "removes a once handler even when it raises" do
    emitter.once(Rosegold::Event::Tick) { raise "handler failed" }
    expect { emitter.emit_event Rosegold::Event::Tick.new }.to raise_error(Exception, "handler failed")
    expect(emitter.event_handlers[Rosegold::Event::Tick]).to be_empty
  end
end
