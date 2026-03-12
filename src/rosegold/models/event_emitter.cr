require "uuid"

class Rosegold::EventEmitter
  alias Handler = NamedTuple(id: UUID, proc: Proc(Event, Nil))
  private alias Handlers = Hash(Event.class, Array(Handler))
  getter event_handlers : Handlers = Handlers.new

  def on(event_type : T.class, id : UUID = UUID.random, &block : T ->) forall T
    event_handlers[event_type] ||= [] of Handler
    {
      id:   id,
      proc: Proc(Event, Nil).new do |event|
        block.call(event.as T)
      end,
    }.tap do |handler|
      event_handlers[event_type] << handler
    end

    id
  end

  def off(event_type : T.class, id : UUID) forall T
    event_handlers[event_type] ||= [] of Handler
    event_handlers[event_type] = event_handlers[event_type].reject do |handler|
      handler[:id] == id
    end
  end

  def once(event_type : T.class, &block : T ->) forall T
    id = UUID.random
    on event_type, id: id do |event|
      block.call event
      off event_type, id
    end
  end

  # Waits for an event. Returns nil on timeout.
  def wait_for(event_type : T.class, timeout : Time::Span = 5.seconds) forall T
    ran_event = nil
    time_start = Time.utc

    once event_type do |event|
      ran_event = event
    end

    until ran_event
      return nil if (Time.utc - time_start) > timeout
      sleep 0.01.seconds
    end

    ran_event
  end

  # Registers listener before running block, then waits. Raises on timeout.
  def wait_for(event_type : T.class, timeout : Time::Span = 5.seconds, &) forall T
    ran_event = nil
    time_start = Time.utc

    once event_type do |event|
      ran_event = event
    end

    yield

    until ran_event
      raise "Timed out waiting for #{event_type} after #{timeout}" if (Time.utc - time_start) > timeout
      sleep 0.01.seconds
    end

    ran_event.not_nil!
  end

  def emit_event(event : Event)
    event_handlers[event.class]?.try &.each(&.[:proc].call(event))
  end
end
