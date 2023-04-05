class Rosegold::Action(T)
  SUCCESS = "" # TODO use unique symbol

  # TODO try channel size 1 so #succeed/#fail aren't rendezvous
  getter channel : Channel(String) = Channel(String).new
  getter target : T

  def initialize(@target : T); end

  def succeed
    @channel.send(SUCCESS)
  end

  def fail(msg : String)
    @channel.send(msg)
  end

  # Throw error if it failed
  def join
    result = channel.receive
    raise Exception.new(result) if result != Action::SUCCESS
  end
end
