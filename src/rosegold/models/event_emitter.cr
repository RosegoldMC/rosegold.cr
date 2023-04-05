abstract class Rosegold::Event; end

class Rosegold::EventEmitter
  private alias Handlers = Hash(Event.class, Array(Proc(Event, Nil)))
  getter event_handlers : Handlers = Handlers.new

  def on(event_type : T.class, &block : T ->) forall T
    event_handlers[event_type] ||= [] of Proc(Event, Nil)
    event_handlers[event_type] << Proc(Event, Nil).new do |event|
      block.call(event.as T)
    end
  end

  def emit_event(event : Event)
    event_handlers[event.class]?.try &.each &.call event
  end
end
