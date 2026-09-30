require "uuid"

# Typed event subscriptions shared by `Bot` and `Client`.
#
# Handlers run synchronously in the emitting fiber. Use `spawn` for work that
# waits for ticks or further packets so the reader can keep receiving events.
class Rosegold::EventEmitter
  alias Handler = NamedTuple(id: UUID, proc: Proc(Event, Nil))
  private alias Handlers = Hash(Event.class, Array(Handler))
  # Registered handlers, grouped by exact event type. Prefer `#on` and `#off`
  # over modifying this registry directly.
  getter event_handlers : Handlers = Handlers.new

  # Registers a handler and returns its UUID for removal with `#off`.
  # Subscriptions match the exact event type, not its subclasses.
  #
  # ```
  # id = bot.on(Rosegold::Event::HealthChanged) { |event| puts event.health }
  # bot.off(Rosegold::Event::HealthChanged, id)
  # ```
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

  # Removes the handler identified by *id* for *event_type*.
  # Does nothing if the handler is already gone.
  def off(event_type : T.class, id : UUID) forall T
    event_handlers[event_type] ||= [] of Handler
    event_handlers[event_type] = event_handlers[event_type].reject do |handler|
      handler[:id] == id
    end
  end

  # Registers a handler for the next matching event and returns its UUID.
  # Removes it before invoking the block, even if the block raises or emits again.
  def once(event_type : T.class, &block : T ->) forall T
    id = UUID.random
    on event_type, id: id do |event|
      off event_type, id
      block.call event
    end
  end

  # Waits for the next matching event, or returns `nil` after *timeout*.
  # Always removes its temporary listener before returning.
  def wait_for(event_type : T.class, timeout : Time::Span = 5.seconds) forall T
    ran_event = nil
    time_start = Time.instant

    id = once event_type do |event|
      ran_event = event
    end

    until ran_event
      return nil if (Time.instant - time_start) > timeout
      sleep 1.milliseconds
    end

    ran_event
  ensure
    off event_type, id if id
  end

  # Registers a listener, runs the block, then waits for the matching event.
  # Returns the event; raises on timeout. The timeout includes time in the block,
  # but cannot interrupt it. The listener is removed even if the block raises.
  #
  # The block triggers the action; it is not an event filter. Any event of the
  # requested type can satisfy the wait, including an unrelated server message.
  def wait_for(event_type : T.class, timeout : Time::Span = 5.seconds, &) forall T
    ran_event = nil
    time_start = Time.instant

    id = once event_type do |event|
      ran_event = event
    end

    yield

    until ran_event
      raise "Timed out waiting for #{event_type} after #{timeout}" if (Time.instant - time_start) > timeout
      sleep 1.milliseconds
    end

    ran_event.as(T)
  ensure
    off event_type, id if id
  end

  # Calls handlers for this exact event type in registration order.
  # Handler exceptions propagate to the caller.
  def emit_event(event : Event)
    event_handlers[event.class]?.try &.each(&.[:proc].call(event))
  end
end
